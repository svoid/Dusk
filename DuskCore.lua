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

local checktype
local assertf
local isifile

local coreOutput

do -- environment setup
	
	local base, overwrite = {}, {} do
		
		base.getgenv = function()
			return genv
		end

		base.iscclosure = function(func)
			return not islclosure(func)
		end

		base.assertcall = function(exp, func, ...)
			if not exp then
				func(...)
			end
			return exp, func, ...
		end

		assertf = function(exp, ...)
			if not exp then
				coreOutput.error(sformat(...), 3)
			end
			return exp, ...
		end
		base.assertf = assertf

		asserttype = function(v, type)
			local vtype = typeof(v)
			if vtype ~= type then
				coreOutput.error(sformat("<%s> expected, got \"%s\"", type, vtype), 3)
			end
		end
		base.asserttype = asserttype

		isifile = function(obj)
			if type(obj) == "table" then
				local meta = getrawmetatable(obj)
				return meta and meta.__type == "File"
			end
		end
		base.isifile = isifile

		isifolder = function(obj)
			if type(obj) == "table" then
				local meta = getrawmetatable(obj)
				return meta and meta.__type == "Folder"
			end
		end
		
		base.isifolder = isifolder
		
		base.printf = function(...)
			coreOutput.print(sformat(...))
		end

		base.warnf = function(...)
			coreOutput.warn(sformat(...))
		end

		base.errorf = function(...)
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

		base.fescape = formatEscape

		local function formatValue(v)
			local vtype = type(v)
			if vtype == "string" then
				v = sformat("\"%s\"", formatEscape(v))
				if settings.print_normalize_string then
					local success, normalized = pcall(unormalize, v)
					v = success and normalized or v
				end
				return v
			elseif vtype == "table" then
				if settings.print_use_type_instead_tostring then
					return "<table>"
				end
				local mt = getrawmetatable(v) or getmetatable(v)
				if mt and mt.__tostring then
					return "[table has __tostring]"
				end
				return v
			elseif vtype == "userdata" then
				vtype = typeof(v)
				if vtype == "Instance" then
					v = sformat(
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
					return sformat(
						"%s(%s)",
						vtype,
						settings.print_use_type_instead_tostring and "<" .. vtype .. ">" or v
					)
				end
			elseif vtype == "vector" then
				return sformat("Vector3(%s)", tostring(v))
			elseif vtype == "function" then
				return formatFunction(v)
			end

			return v
		end

		base.rprint = constants.print
		overwrite.print = function(...)
			local str = ""
			for i = 1, select('#', ...) do
				local v = tostring(formatValue(select(i, ...)))
				assert(type(v) == "string", "'tostring' must return a string to 'print'")
				str = str .. v .. " "
			end
			constants.print(str)
		end

		base.rwarn = constants.warn
		overwrite.warn = function(...)
			local str = ""
			for i = 1, select('#', ...) do
				local v = tostring(formatValue(select(i, ...)))
				assert(type(v) == "string", "'tostring' must return a string to 'warn'")
				str = str .. v .. " "
			end
			constants.warn(str)
		end

		base.printl = function(t)
			local print = coreOutput.print

			for i, v in pairs(t) do
				print(i, formatValue(v))
			end
		end

		local printedTables = {}
		base.printe = function(...)
			local print = coreOutput.print
			local tab = settings.print_tab_string
			local maxLayer = settings.printe_max_layer

			local layer = 0
			tclear(printedTables)

			local printl
			function printl(t)
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

			local v
			for i = 1, select('#', ...) do
				v = select(i, ...)
				if type(v) == "table" then
					printl(v)
				else
					print(v)
				end
			end
		end

		local rawrequire = require

		overwrite.require = function(obj)
			if isifile(obj) then
				local chunk, err = loadstring(obj:Read())
				if chunk then
					return chunk()
				end
				error(err)
			end
			return rawrequire(obj)
		end
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

		function EnumItem.new(enum, name)
			asserttype(name, "string")

			local self = {}
			self[nametag] = name
			self[parenttag] = enum
			return setmetatable(self, EnumItem)
		end
	end

	local Enum do
		Enum = {
			__index = function(self, k)
				errorf("\"%s\" is not a valid member of enum %s", self[nametag])
			end,
			__tostring = function(self)
				return self[nametag]
			end
		}

		function Enum.new(name, t)
			asserttype(name, "string")
			assertf(rawget(DEnums, name) == nil, "enum %s already exist", name)

			local self = {}
			DEnums[name] = self
			self[nametag] = name

			for _, itemName in pairs(t) do
				self[itemName] = EnumItem.new(self, itemName)
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
	
	lockclass(osinstance)
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
			local wipedTables = {}
			
			local wipe
			function wipe(t)
				if tfind(wipedTables, t) then return end
				tinsert(wipedTables, t)
				
				for i, v in pairs(t) do
					local vtype = typeof(v)
					if vtype == "table" then
						wipe(v)
					elseif vtype == "RBXScriptConnection" then
						v:Disconnect()
					end
					rawset(t, i, nil)
				end
			end
			
			function recursiveWipe(t)
				wipe(t)
				tclear(wipedTables)
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
		
		function module.new(moduleFile)
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
			local chunk, err = loadstring(
				"local module = core._Temp.CurrentModule;" ..
				"core._Temp.CurrentModule = nil;" ..
				"local moduledata = module._Data;" ..
				"local globalstorage = storage;" ..
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
		return loadedModules[name]
	end
	
	function moduleProvider:GetLoadedModules()
		return loadedModules
	end
	
	function moduleProvider:UnloadModule(name)
		local module = loadedModules[name]
		assertf(module, "module \"%s\" is not loaded", name)
		module:Unload()
	end

	function moduleProvider:LoadModule(name)
		local moduleFile = core.Modules[name]
		assertf(moduleFile, "cannot find module \"%s\"", name)
		return module.new(moduleFile)
	end

	function moduleProvider:LoadClearModule(name)
		if self:GetModule(name) then
			self:UnloadModule(name)
		end
		self:LoadModule(name)
	end
	
	function moduleProvider:Include(name)
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
	
	function core:GetService(name)
		return loadedServices[name]
	end
	
	local function newService(serviceFile)
		local serviceName = serviceFile.Name
		assertf(loadedServices[serviceName] == nil, "service \"%s\" already loaded", serviceName)

		local methods = {}
		local fields = {
			ClassName = serviceName
		}

		local service = {
			_Methods = methods,
			_Fields = fields,
			
			__index = function(_, index)
				asserttype(index, "string")

				for i, v in pairs(methods) do
					if i == index then
						return v
					end
				end

				for i, v in pairs(fields) do
					if i == index then
						return v
					end
				end

				errorf("\"%s\" is not a valid member of \"%s\"", index, serviceName)
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
		local chunk, err = loadstring(
			"service = core._Temp.CurrentService;" ..
			"core._Temp.CurrentService = nil;" ..
			"methods = service._Methods;" ..
			"fields = service._Fields;" ..
			"service = nil;" ..
			"globalstorage = storage;" ..
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
	

	--[[
			Main
	--]]
	
	
	function core.new()
		local self = setmetatable({}, core)
		core = self
		setreadonly(self, true)
		genv.core = self
		
		for _, service in ipairs(self.Services:GetChildren()) do
			if service:IsA("File") then
				coroutine.wrap(newService)(service)
			end
		end
		
		for _, module in ipairs(self.InitModules:GetChildren()) do
			if module:IsA("File") then
				coroutine.wrap(self._LoadInitModule)(self, module)
			end
		end
		
		return self
	end
	
	core.new()
end
