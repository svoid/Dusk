if _G.EnvSettings then return end

local genv = getgenv()

local constants = {
	print = print,
	warn = warn,
	error = error
}

setreadonly(constants, true)
_G.EnvConstants = constants

local settings = {
	printe_max_layer = 12,
	print_tab_string = "    ", -- console shortens \t
	print_use_type_instead_tostring = true,
	print_ignore_tostring_metatable = false,
	print_add_instance_class_name = true,
	print_normalize_string = true,
	print_add_closure_type = true,
}
_G.EnvSettings = settings


local type = type
local typeof = typeof
local tostring = tostring
local pcall = pcall
local rawset = rawset
local select = select
local pairs = pairs
local ipairs = ipairs
local loadstring = loadstring
local getmetatable = getmetatable
local setmetatable = setmetatable
local getrawmetatable = getrawmetatable

local tfind = table.find
local tclear = table.clear
local tinsert = table.insert
local tremove = table.remove
local srep = string.rep
local sformat = string.format
local sgsub = string.gsub
local sreverse = string.reverse
local unormalize = utf8.nfdnormalize

local islclosure = islclosure
local readfile = readfile
local appendfile = appendfile
local writefile = writefile
local listfiles = listfiles
local isfile = isfile
local isfolder = isfolder
local delfolder = delfolder
local delfile = delfile

local assertf
local isifile

local coreOutput

do -- environment setup
	
	local base, overwrite = {}, {} do
		function assertf(exp, ...)
			if not exp then
				coreOutput.error(sformat(...), 3)
			end
			return exp, ...
		end
		
		function isifile(obj)
			if type(obj) == "table" then
				local meta = getrawmetatable(obj)
				return meta and meta.__type == "File"
			end
		end
		
		local function iscclosure(func)
			return not islclosure(func)
		end
		
		local function assertcall(exp, func, ...)
			if not exp then
				func(...)
			end
			return exp, func, ...
		end
		
		local function tobool(v)
			return (v == 1 or v == "true" or v == "1" or v == true) and true or false
		end
		
		local canaccesspermission = function(identity, permission)
			if not permission then
				return true
			end
			if identity == 1 or identity == 4 then
				return tobool(bit32.band((permission - 1), 0xFFFFFFFD))
			elseif identity == 3 or identity == 6 then
				return not tobool((bit32.band((permission - 1), 0xFFFFFFF9))) and permission ~= 7
			elseif identity == 5 then
				return permission == 1
			elseif identity == 7 or identity == 8 then
				return true
			elseif identity == 9 then
				return permission - 4 <= 1
			else
				return false
			end
		end
		
		local function asserttype(v, type)
			local vtype = typeof(v)
			if vtype ~= type then
				coreOutput.error(sformat("<%s> expected, got \"%s\"", type, vtype), 3)
			end
		end
		
		local function isifolder(obj)
			if type(obj) == "table" then
				local meta = getrawmetatable(obj)
				return meta and meta.__type == "Folder"
			end
		end
		
		local function printf(...)
			coreOutput.print(sformat(...))
		end
		
		local function warnf(...)
			coreOutput.warn(sformat(...))
		end
		
		local function errorf(...)
			coreOutput.error(sformat(...), 2)
		end

		local function formatFunction(func)
			if settings.print_use_type_instead_tostring then
				if settings.print_add_closure_type then
					return islclosure(func) and "<lclosure>" or "<cclosure>"
				end
				return "<function>"
			end
			return func
		end

		local formatEscape do
			local pattern = "[\\\a\b\f\n\r\t\v\"\']"
			local escape = {
				['\\'] = '\\\\',
				['\a'] = '\\a',
				['\b'] = '\\b',
				['\f'] = '\\f',
				['\n'] = '\\n',
				['\r'] = '\\r',
				['\t'] = '\\t',
				['\v'] = '\\v',
				['\"'] = '\\"',
				['\''] = '\\\''
			}

			function formatEscape(str)
				return sgsub(str, pattern, escape)
			end
		end

		local function formatValue(v)
			local vtype = type(v)
			if vtype == "string" then
				v = string.format("\"%s\"", formatEscape(v))
				if settings.print_normalize_string then
					local success, normalized = pcall(unormalize, v)
					v = success and normalized or v
				end
				return v
			elseif vtype == "table" then
				if settings.print_use_type_instead_tostring then
					local mt = getmetatable(v)
					if mt and rawget(mt, "__tostring") and settings.print_ignore_tostring_metatable then
						return tostring(v)
					end
					return "<table>"
				end
				local mt = getmetatable(v)
				if mt and rawget(mt, "__tostring") and not settings.print_ignore_tostring_metatable then
					return "*** table has __tostring ***"
				end
				return v
			elseif vtype == "userdata" then
				vtype = typeof(v)
				if vtype == "Instance" then
					v = string.format(
						"Instance: %s\"%s\"",
						settings.print_add_instance_class_name and v.ClassName .. ": " or "",
						formatEscape(v:GetFullName())
					)
					
					if settings.print_normalize_string then
						local success, normalized = pcall(unormalize, v)
						return success and normalized or v
					end
					return v
				else
					return string.format(
						"%s(%s)",
						vtype,
						settings.print_use_type_instead_tostring and "<" .. vtype .. ">" or v
					)
				end
			elseif vtype == "vector" then
				return string.format("Vector3(%s)", tostring(v))
			elseif vtype == "function" then
				return formatFunction(v)
			end
			
			return v
		end
		
		local function processformattedoutput(...)
			local str = ""
			for i = 1, select('#', ...) do
				local v = tostring(formatValue(select(i, ...)))
				assert(type(v) == "string", "'tostring' must return a string to 'print'")
				str ..= v .. " "
			end
			return str
		end
		
		local function processoutput(...)
			local str = ""
			for i = 1, select('#', ...) do
				local v = tostring(tostring(select(i, ...)))
				assert(type(v) == "string", "'tostring' must return a string to 'print'")
				str ..= v .. " "
			end
			return str
		end
		
		local function overwrite_print(...)
			constants.print(processformattedoutput(...))
		end
		
		local function overwrite_warn(...)
			constants.warn(processformattedoutput(...))
		end
		
		
		local function printl(t)
			local print = coreOutput.print
			
			for i, v in pairs(t) do
				print(i, formatValue(v))
			end
		end

		local printedTables = {}
		local function printe(...)
			local print = coreOutput.print
			local tab = settings.print_tab_string
			local maxLayer = settings.printe_max_layer

			local layer = 0
			tclear(printedTables)

			local function printl(t)
				if layer == maxLayer then return end

				local tab = srep(tab, layer)

				if tfind(printedTables, t) then
					print(tab, "*** already printed ***")
					return
				end
				printedTables[#printedTables + 1] = t

				for i, v in pairs(t) do
					print(tab, i, formatValue(v))
					if type(v) == "table" then
						layer = layer + 1
						printl(v)
						layer = layer - 1
					end
				end
			end

			for i = 1, select("#", ...) do
				local v = select(i, ...)
				if type(v) == "table" then
					printl(v)
				else
					print(v)
				end
			end
		end
		
		local rawrequire = require

		local function overwrite_require(obj)
			if isifile(obj) then
				local chunk, err = loadstring(obj:Read())
				if chunk then
					return chunk()
				end
				error(err)
			end
			return rawrequire(obj)
		end
		
		
		base.iscclosure = iscclosure
		base.assertcall = assertcall
		base.tobool = tobool
		base.canaccesspermission = canaccesspermission
		base.assertf = assertf
		base.asserttype = asserttype
		base.isifile = isifile
		base.isifolder = isifolder
		base.printf = printf
		base.warnf = warnf
		base.errorf = errorf
		base.fescape = formatEscape
		base.rprint = constants.print
		base.rwarn = constants.warn
		base.printl = printl
		base.printe = printe
		
		base.processoutput = processoutput
		base.processformattedoutput = processformattedoutput
		overwrite.print = overwrite_print
		overwrite.warn = overwrite_warn
		overwrite.require = overwrite_require
	end


	local function setGlobal(index, value)
		genv[index] = value
	end

	local function wrapFunction(func)
		if islclosure(func) then
			return newcclosure(func)
		end
		return func
	end

	local function checkFunction(name, func, overwrite)
		if overwrite or not genv[name] then
			setGlobal(name, wrapFunction(func))
		end
	end

	for name, func in pairs(base) do
		checkFunction(name, func)
	end

	for name, func in pairs(overwrite) do
		checkFunction(name, func, true)
	end

end

local function lockclass(t, type)
	t.__type = type
	t.__metatable = "The metatable is locked"
	t.__protected = true
	setreadonly(t, true)
end

local function inherit(childMeta, baseMeta)
	for i, v in pairs(baseMeta) do
		childMeta[i] = v
	end
	return childMeta
end

genv.oop = {
	lockclass = lockclass,
	inherit = inherit
}


--[[
		Enums
--]]


local DEnums do
	local nametag = math.random()
	local parenttag = math.random()

	DEnums = setmetatable({}, {
		__index = function(_, k)
			errorf("\"%s\" is not a valid member of DEnums", k)
		end,

		__tostring = function()
			return "DEnums"
		end
	})


	local EnumItem do
		EnumItem = {
			__index = function(self, k)
				errorf("\"%s\" is not a valid member of %s.%s", self[parenttag][nametag], self[nametag])
			end,
			__tostring = function(self)
				return string.format("DEnums.%s.%s", self[parenttag][nametag], self[nametag])
			end
		}

		function EnumItem.new(enum, name, value)
			asserttype(name, "string")

			local self = {}
			self[nametag] = name
			self[parenttag] = enum
			self.Value = value
			return setmetatable(self, EnumItem)
		end
	end

	local Enum do
		Enum = {
			__index = function(self, k)
				errorf("\"%s\" is not a valid member of enum %s", k, self[nametag])
			end,
			__tostring = function(self)
				return self[nametag]
			end
		}

		function Enum.new(name, t, hasValue)
			asserttype(name, "string")
			assertf(rawget(DEnums, name) == nil, "enum %s already exist", name)

			local self = {}
			DEnums[name] = self
			self[nametag] = name
			
			if hasValue then
				for itemName, value in pairs(t) do
					self[itemName] = EnumItem.new(self, itemName, value)
				end
			else
				for _, itemName in pairs(t) do
					self[itemName] = EnumItem.new(self, itemName)
				end
			end

			return setmetatable(self, Enum)
		end
	end

	genv.DEnums = DEnums
	genv.NewEnum = Enum.new
end


--[[
		Output handler
--]]


local ohandler = {} do
	
	function ohandler.new(functions)
		local self = setmetatable({}, ohandler)
		
		for name, func in pairs(functions) do
			asserttype(name, "string")
			asserttype(func, "function")
			self[name] = func
		end

		return self
	end
	
	genv.OHandler = ohandler
	lockclass(ohandler, "OutputHandler")
end


--[[
		Workspace filesystem
--]]


local osinstance = {} do
	osinstance.__index = osinstance

	function osinstance:Destroy()
		local parentChildren = osinstance.Parent.Children
		tremove(parentChildren, tfind(parentChildren, self))
		if self.__type == "Folder" then
			delfolder(self.Path)
		elseif self.__type == "File" then
			delfile(self.Path)
		end
	end
	
	function osinstance:IsA(className)
		return self.ClassName == className
	end
	
	lockclass(osinstance, "osinstance")
end

local file
local folder = {} do
	local meta = inherit(folder, osinstance)
	folder.__index = function(self, i)
		local member = meta[i]
		if member then
			return member
		end

		for _, child in ipairs(self.Children) do
			if child.Name == i or child.FullName == i then
				return child
			end
		end
	end

	folder.ClassName = "Folder"

	function folder.new(path)
		local self = setmetatable({}, folder)
		self.Path = path
		self.Name = sgsub(path, "[^\\]+\\", "")
		self.FullName = self.Name
		self.Children = {}
		return self
	end

	function folder:_AddChild(child)
		child.Parent = self
		tinsert(self.Children, child)
	end
	
	function folder:CreateFolder(fullName)
		local path = self.Path .. "\\" .. fullName
		makefolder(path)
		local newFolder = folder.new(path)
		self:_AddChild(newFolder)
		return newFolder
	end
	
	function folder:CreateFile(fullName, str)
		local path = self.Path .. "\\" .. fullName
		writefile(path, str or "")
		local newFile = file.new(path)
		self:_AddChild(newFile)
		return newFile
	end
	
	function folder:GetChildren()
		local children = {}
		for i, child in ipairs(self.Children) do
			children[i] = self.Children[i]
		end
		return children
	end

	function folder:GetFolder(name)
		local osinstance = self[name]
		if osinstance then
			assertf(
				osinstance:IsA("Folder"),
				"\"%s\" has invalid type of osinstance, \"%s\"",
				name,
				osinstance.ClassName
			)
			return osinstance
		end
		return self:CreateFolder(name)
	end

	function folder:GetFile(name)
		local osinstance = folder[name]
		if osinstance then
			assertf(
				osinstance:IsA("File"),
				"\"%s\" has invalid type of osinstance, \"%s\"",
				name,
				osinstance.ClassName
			)
			return osinstance
		end
		return self:CreateFile(name)
	end

	lockclass(folder, folder.ClassName)
end

file = {} do
	file.__index = inherit(file, osinstance)

	file.ClassName = "File"

	function file.new(path)
		local self = setmetatable({}, file)
		self.Path = path
		self.FullName = sgsub(path, "[^\\]+\\", "")
		self.Name = sgsub(self.FullName, "%.%a+$", "")
		self.Extension = sgsub(self.FullName, ".+%.", "")
		return self
	end

	function file:Read()
		return readfile(self.Path)
	end

	function file:Append(str)
		return appendfile(self.Path, str)
	end

	function file:Write(str)
		return writefile(self.Path, str)
	end
	
	function file:GetChildren()
		return {}
	end
	
	lockclass(file, file.ClassName)
end

local scanFolder
function scanFolder(parent)
	for _, path in ipairs(listfiles(parent.Path)) do
		if isfile(path) then
			parent:_AddChild(file.new(path))
		elseif isfolder(path) then
			local child = folder.new(path)
			parent:_AddChild(child)
			scanFolder(child)
		end
	end
end

local workspaceRoot = folder.new("")
genv.Storage = workspaceRoot
genv.storage = workspaceRoot
scanFolder(workspaceRoot)


--[[
		Core
--]]


local core
local moduleProvider = {} do
	moduleProvider.__index = moduleProvider
	
	local loadedModules = {}
	
	local module = {} do
		module.__index = module
		
		local function disableConnections(t)
			for _, conn in ipairs(t) do
				conn:Disconnect()
			end
		end
		
		local recursiveWipe do
			local wipe
			function wipe(t)
				for i, v in pairs(t) do
					rawset(t, i, nil)
					local vtype = typeof(v)
					if vtype == "table" then
						wipe(v)
					elseif vtype == "RBXScriptConnection" then
						v:Disconnect()
					end
				end
			end
			
			function recursiveWipe(t)
				wipe(t)
			end
		end
		
		function module:Unload(...)
			if self._CustomUnload then
				pcall(self._CustomUnload, self, ...)
			end
			
			setreadonly(self, false)
			disableConnections(self._CoreConnections)
			loadedModules[self._Name] = nil
			recursiveWipe(self)
		end
		
		function module:Reload(...)
			core:ReloadModule(self._Name)
			disableConnections(self._CoreConnections)
			tclear(self._CoreConnections)
			recursiveWipe(self._Data)
		end
		
		function module:AddCoreConnection(conn)
			asserttype(conn, "RBXScriptConnection")
			setreadonly(self, false)
			tinsert(self._CoreConnections, conn)
			setreadonly(self, true)
		end

		function module:SetUnload(func)
			if func then
				asserttype(func, "function")
			end
			setreadonly(self, false)
			self._CustomUnload = func
			setreadonly(self, true)
		end
		
		function module:GetStorage()
			return core.ModuleStorage:GetFolder(self._Name)
		end
		
		function module.new(moduleFile, ...)
			local name = moduleFile.Name
			assertf(moduleProvider:GetModule(name) == nil, "module \"%s\" already loaded", name)
			
			local self = setmetatable({}, module)
			loadedModules[name] = self
			
			self._Name = name
			self._Data = {}
			self._CoreConnections = {}
			self.Active = true
			
			-- create global variables in script
			core._Temp.CurrentModule = self
			core._Temp.Arguments = {...}
			local chunk, err = loadstring(sgsub([[
				module = core._Temp.CurrentModule;
				moduledata = module._Data;
				modulearguments = core._Temp.Arguments
				globalstorage = storage;
				core._Temp.CurrentModule = nil;
				core._Temp.Arguments = nil;]], "\n", " ") ..
				moduleFile:Read(),
				name
			)
			
			if chunk then
				setreadonly(self, true)
				return self, chunk()
			end
			
			error(err, 3)
		end
	end

	function moduleProvider:GetModule(name)
		asserttype(name, "string")
		return loadedModules[name]
	end
	
	function moduleProvider:GetLoadedModules()
		return loadedModules
	end
	
	function moduleProvider:UnloadModule(name)
		asserttype(name, "string")
		local module = loadedModules[name]
		assertf(module, "module \"%s\" is not loaded", name)
		module:Unload()
	end

	function moduleProvider:LoadModule(name)
		asserttype(name, "string")
		local moduleFile = core.Modules[name]
		assertf(moduleFile, "cannot find module \"%s\"", name)
		return module.new(moduleFile)
	end

	function moduleProvider:LoadClearModule(name)
		asserttype(name, "string")
		if self:GetModule(name) then
			self:UnloadModule(name)
		end
		self:LoadModule(name)
	end
	
	function moduleProvider:Include(name)
		asserttype(name, "string")
		local module = self:GetModule(name) or self:LoadModule(name)
		asserttype(module._Data.ModuleFields, "table", "Included modules must contain table \"ModuleFields\" in moduledata")
		return module._Data.ModuleFields
	end
	
	function moduleProvider:ReloadModule(name)
		local module = loadedModules[name]
		assertf(name, "module \"%s\" is not loaded", name)
		self:UnloadModule(name)
		self:LoadModule(name)
	end

	function moduleProvider:_LoadInitModule(moduleFile)
		return module.new(moduleFile)
	end
end


core = {} do
	core.__index = inherit(core, moduleProvider)
	
	core._Temp = {}
	
	local coreRoot = workspaceRoot:GetFolder("Dusk")
	core.InitModules = coreRoot:GetFolder("InitModules")
	core.Modules = coreRoot:GetFolder("Modules")
	core.ModuleStorage = coreRoot:GetFolder("ModuleStorage")
	core.Services = coreRoot:GetFolder("Services")
	
	
	--[[
			Flags
	--]]
	
	
	local flags = {
		UseConsoleOutput = false
	}
	
	function core:GetFlag(name)
		return flags[name]
	end
	
	function core:SetFlag(name, value)
		local vtype = type(value)
		assertf(
			vtype == "boolean" or vtype == "number" or vtype == "string",
			"<boolean, number, string> expected, got\"%s\"",
			vtype
		)
		flags[name] = value
	end
	
	
	--[[
			Output
	--]]
	
	
	local function corePrint(...)
		if flags.UseConsoleOutput then
			rconsoleprint(...)
		else
			constants.print(...)
		end
	end

	local function coreWarn(...)
		if flags.UseConsoleOutput then
			rconsolewarn(...)
		else
			constants.warn(...)
		end
	end
	
	coreOutput = ohandler.new({
		print = corePrint,
		warn = coreWarn,
		error = constants.error,
	})
	
	function core:GetOutput()
		return coreOutput
	end
	
	
	--[[
			Services
	--]]
	
	
	local loadedServices = {}
	
	local function newService(serviceFile)
		local serviceName = serviceFile.Name
		assertf(loadedServices[serviceName] == nil, "service \"%s\" already loaded", serviceName)
		
		if serviceFile:IsA("Folder") then
			serviceFile = serviceFile.Main
		end
		
		local methods = {}
		local fields = {
			ClassName = serviceName
		}

		local service = {
			_Methods = methods,
			_Fields = fields,
			
			__index = function(_, index)
				asserttype(index, "string")
				return methods[index]
					or fields[index]
					or errorf("\"%s\" is not a valid member of \"%s\"", index, serviceName)
			end,
			
			__newindex = function(_, index, newValue)
				asserttype(index, "string")
				asserttype(newValue, typeof(fields[index]))
				fields[index] = newValue
			end
		}

		local proxy = setmetatable({}, service)
		
		-- create global variables in service
		core._Temp.CurrentService = service
		core._Temp.CurrentServiceStorage = core.Services ~= serviceFile.Parent and serviceFile.Parent
		local chunk, err = loadstring(sgsub([[
			service = core._Temp.CurrentService;
			storage = core._Temp.CurrentServiceStorage;
			methods = service._Methods;
			fields = service._Fields;
			globalstorage = storage;
			core._Temp.CurrentService = nil;
			core._Temp.CurrentServiceFile = nil;
			service = nil;]], "\n", " ") ..
			serviceFile:Read(),
			serviceName
		)

		if chunk then
			chunk()
			lockclass(service, serviceName)
			loadedServices[serviceName] = proxy
			return proxy
		end

		error(err, 3)
	end
	
	function core:GetService(name)
		return loadedServices[name] or newService(assert(self.Services[name], "invalid service name"))
	end

	--[[
			Main
	--]]
	
	
	function core.new()
		local self = setmetatable({}, core)
		core = self
		setreadonly(self, true)
		genv.core = self
		
		for _, module in ipairs(self.InitModules:GetChildren()) do
			if module:IsA("File") then
				coroutine.wrap(self._LoadInitModule)(self, module)
			end
		end
		
		return self
	end
	
	core.new()
end
