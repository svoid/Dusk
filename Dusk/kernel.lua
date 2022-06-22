local DUSK_THREAD_IDENTITY = 8
local CORE_FOLDER = "Dusk"
local BASE_LIB_PATH = CORE_FOLDER .. "//blib.lua"
local SETTINGS_PATH = CORE_FOLDER .. "//kernel.config"
local FS_PATH = CORE_FOLDER .. "//fs.lua"
local HOOK_HANDLER_PATH = CORE_FOLDER .. "//hooks.lua"
local USER_PATH = CORE_FOLDER .. "//user.lua"
local AUDITOR_LOG_PATH = CORE_FOLDER .. "log.txt"

local raw_readfile = readfile
local raw_writefile = writefile
local raw_appendfile = appendfile

local function loadfile(path, name)
	return loadstring(raw_readfile(path), name)
end

syn.set_thread_identity(DUSK_THREAD_IDENTITY)


--[[
		Boot
--]]



local untrustedEnvironment = getgenv()
local trustedEnvironment = setmetatable({}, {__index = getrenv()})

local duskGlobalEnvironment = getfenv()
setrawmetatable(duskGlobalEnvironment, {__index = untrustedEnvironment})

local rawSettings

local fs
local baseLibrary

local DuskObject
local KernelObject

local rootFolder

local patchHandler

do
	local initData = {
		UntrustedEnvironment = untrustedEnvironment,
		TrustedEnvironment = trustedEnvironment
	}
	
	
	local function loadSettings()
		rawSettings = game:GetService("HttpService"):JSONDecode(raw_readfile(SETTINGS_PATH))
		initData.RawSettings = rawSettings
	end
	
	local function loadBaseLibrary()
		baseLibrary = assert(loadfile(BASE_LIB_PATH, "blib")(initData))
		initData.BaseLibrary = baseLibrary
	end
	
	local function loadFileSystem()
		fs = assert(loadfile(FS_PATH, "fs")(initData))
		trustedEnvironment.fs = fs
		rootFolder = initData.RootFolder
	end
	
	
	local function createMainBaseClasses()
		
		DuskObject = {} do
			
			function DuskObject:IsA(classOrName)
				if type(classOrName) == "string" then
					return self.__type == classOrName
				end
				
				return self.__index == classOrName
			end
			
			local function recursiveBaseTableClassSearch(t, name)
				for _, class in ipairs(t) do
					if class.__type == name then
						return class
					else
						local result = recursiveBaseTableClassSearch(class.__base, name)
						if result then
							return result
						end
					end
				end
			end
			
			function DuskObject:IsDerivedOf(class)
				local vtype = type(class)
				
				if vtype == "string" then
					return not not recursiveBaseTableClassSearch(self.__base, class)
				end
				
				baseLibrary.expectClass(class)
				
				return not not recursiveBaseTableClassSearch(self.__base, class.__type)
			end
			
			function DuskObject:IsDerivedOfOrSameClass(class)
				baseLibrary.expectClass(class)
				
				return self.__index == class.__index or self:IsDerivedOf(class)
			end
			
			baseLibrary.buildFinalClass("DuskObject", DuskObject)
		end
		
		initData.DuskObject = DuskObject
		
		KernelObject = {} do
			baseLibrary.buildFinalClass("KernelObject", KernelObject, DuskObject)
		end
	end
	
	local function createPatchHandler()
		
		local expectType = baseLibrary.expectType
		
		local PatchHandler = {} do
			
			local Patch = {} do
				
				function Patch.new(patchFunc, repairFunc)
					local self = setmetatable({}, Patch)
					
					self._PatchFunction = patchFunc
					self._RepairFunction = repairFunc
					self._UserData = {}
					
					return self
				end
				
				function Patch:GetUserData()
					return self._UserData
				end
				
				function Patch:Run()
					self._PatchFunction()
				end
				
				function Patch:Repair()
					self._RepairFunction()
				end
				
				function Patch:Destroy()
					self:Repair()
					table.clear(self._UserData)
				end
				
				baseLibrary.buildFinalClass("Patch", Patch, DuskObject)
			end
			
			function PatchHandler.new()
				local self = setmetatable({}, PatchHandler)
				
				self._Patches = {}
				
				return self
			end
			
			function PatchHandler:Destroy()
				for _, patch in ipairs(self._Patches) do
					patch:Destroy()
				end
			end
			
			function PatchHandler:NewPatch(patchFunc, repairFunc)
				expectType(patchFunc, "function")
				expectType(repairFunc, "function")
				
				local patch = Patch.new(patchFunc, repairFunc)
				table.insert(self._Patches, patch)
				return patch
			end
			
			baseLibrary.buildFinalSingleton("PatchHandler", PatchHandler, KernelObject)
		end
		
		patchHandler = PatchHandler.new()
		initData.PatchHandler = patchHandler
	end
	
	local function createEnvironment()
		initData.Environment = trustedEnvironment
	end
	
	-- no requirements
	loadSettings()
	createEnvironment()
	
	-- settings
	loadBaseLibrary()
	
	-- base lib
	createMainBaseClasses()
	
	-- base class, base lib
	createPatchHandler()
	
	-- everything
	loadFileSystem()
	
end



--[[
		Kernel
--]]


local kernel

local kernelVariables = {} do
	kernelVariables.KernelFolder = rootFolder.Dusk
	
	kernelVariables.KernelLibraries = kernelVariables.KernelFolder.Libs
	kernelVariables.UserLibraries = rootFolder.UserLibs

	kernelVariables.KernelModules = kernelVariables.KernelFolder.Modules
	kernelVariables.UserModules = rootFolder.UserModules
end

local kernelSettings do
	
	local KernelSettings = {} do
		
		function KernelSettings.new(rawSettings)
			local self = setmetatable({}, KernelSettings)
			
			self._Data = rawSettings
			
			return self
		end
		
		function KernelSettings:GetField(name)
			return self._Data[name]
		end
		
		function KernelSettings:SetField(name, value)
			self._Data[name] = value
			self:_Save()
		end
		
		function KernelSettings:_Save()
			writefile(SETTINGS_PATH, game:GetService("HttpService"):JSONEncode(self.Data))
		end
		
		baseLibrary.buildFinalSingleton("KernelSettings", KernelSettings)
	end
	
	kernelSettings = KernelSettings.new(rawSettings)
end


local kernelAuditor do
	
	local KernelAuditor = {} do
		
		function KernelAuditor.new()
			local self = setmetatable({}, KernelAuditor)
			
			self.Buffer = ""
			self.BufferSize = 0
			
			self.BufferWriteIndex = 0
			self.MaxBufferSize = 2000
			
			self.NoDelay = false
			self.WriteDelayTime = 5
			self.LastBufferInputTime = 0
			self.FirstBufferInputTime = nil
			
			raw_writefile(AUDITOR_LOG_PATH, "")
			
			return self
		end
		
		function KernelAuditor:Write()
			raw_appendfile(AUDITOR_LOG_PATH, self.Buffer)
			self.Buffer = ""
			self.BufferSize = 0
			self.FirstBufferInputTime = nil
		end
		
		local printLog = kernelSettings:GetField("PrintKernelLog")
		function KernelAuditor:Log(content)
			if printLog then
				print(content)
			end
			
			content ..= "\n"
			raw_appendfile(AUDITOR_LOG_PATH, content)
			
			-- TODO: implement file buffer class
			--[[
			self.Buffer ..= content
			self.BufferSize = #self.Buffer
			
			if not self.FirstBufferInputTime then
				self.FirstBufferInputTime = tick()
			end
			
			if self.BufferSize > self.MaxBufferSize 
				or self.FirstBufferInputTime > self.WriteDelayTime
			then
				self:Write()
			end
			]]
		end
		
		baseLibrary.buildFinalSingleton("KernelAuditor", KernelAuditor, KernelObject)
	end
	
	kernelAuditor = KernelAuditor.new()
end

local libraryHandler do
	
	local LibraryHandler = {} do
		
		local LibraryHelper = {} do
			
			function LibraryHelper.new(library, name)
				local self = setmetatable({}, LibraryHelper)
				
				self.Name = name
				self.Library = library
				
				return self
			end
			
			function LibraryHelper:Destroy()
				self.Library = nil
			end
			
			baseLibrary.buildFinalClass("LibraryHelper", LibraryHelper, KernelObject)
		end
		
		function LibraryHandler.new()
			local self = setmetatable({}, LibraryHandler)
			
			self._Helpers = {}
			
			return self
		end
		
		function LibraryHandler:Destroy()
			for i, helper in ipairs(self._Helpers) do
				helper:Destroy()
			end
			table.clear(self._Helpers)
		end
		
		-- return library content
		function LibraryHandler:GetLoadedLibrary(name)
			for _, helper in ipairs(self._Helpers) do
				if helper.Name == name then
					return helper.Library
				end
			end
		end
		
		function LibraryHandler:FindLibraryFile(name)
			return kernelVariables.KernelLibraries[name]
				or  kernelVariables.UserLibraries[name]
		end
		
		-- get library content, loaded it if its not loaded yet
		function LibraryHandler:GetLibrary(name)
			local library = self:GetLoadedLibrary(name)
			if library then
				return library
			end
			
			local libraryFile = self:FindLibraryFile(name)
			if libraryFile then
				return self:_RunLibrary(libraryFile)
			end
		end
		
		function LibraryHandler:AddLibrary(library, name)
			local helper = LibraryHelper.new(library, name)
			table.insert(self._Helpers, helper)
			return library
		end
		
		-- run library file and return it's content
		function LibraryHandler:_RunLibrary(libraryFile)
			kernelAuditor:Log("LibraryHandler:RunLibrary:", libraryFile.Path)
			
			local libraryName = libraryFile.Name
			local closure = loadstring(libraryFile:Read(), libraryName)
			assert(type(closure) ~= "string", closure)
			
			local libraryContent = closure()
			self:AddLibrary(libraryContent, libraryName)
			
			return libraryContent
		end
		
		-- run library file
		function LibraryHandler:InitLibrary(nameOrFile)
			if type(nameOrFile) == "string" then
				self:GetLibrary(nameOrFile)
			else
				local libraryFile = baseLibrary.expectClass(nameOrFile, "File")
				if not self:GetLoadedLibrary(nameOrFile.Name) then
					self:_RunLibrary(libraryFile)
				end
			end
		end
		
		baseLibrary.buildFinalSingleton("LibraryHandler", LibraryHandler, KernelObject)
	end
	
	libraryHandler = LibraryHandler.new()
end


local userModuleHandler, kernelModuleHandler do
	
	local BaseModule = {} do
		
		function BaseModule.new(name, closure)
			local self = setmetatable({}, BaseModule)
			
			self.Name = name
			
			self.Environment = getfenv(closure)
			self.Active = false
			self.Result = nil
			
			self._Garbage = {}
			
			-- temp value
			self.Closure = closure
			
			return self
		end
		
		local function recursiveClear(t)
			local metatable = getrawmetatable(t)
			if metatable then
				setrawmetatable(t, nil)
				recursiveClear(metatable)
			end
			
			for i, v in pairs(t) do
				
				t[i] = nil
				
				local vtype = typeof(v)
				if vtype == "table" then
					
					if t.__type and t:IsDerivedOfOrSameClass(KernelObject) then
						return
					end
					
					recursiveClear(t)
				elseif vtype == "RBXScriptConnection" then
					v:Disconnect()
				end
				
			end
		end
		
		function BaseModule:Run(...)
			local closure = self.Closure
			self.Closure = nil
			
			self.Environment.module = self
			
			self.Active = true
			local result = {closure(...)}
			
			self.Result = result
			return unpack(result)
		end
		
		function BaseModule:Destroy()
			self.Active = false
			recursiveClear(self._Garbage)
		end
		
		function BaseModule:AddGarbage(...)
			local garbage = self._Garbage
			for i = 1, select("#", ...) do
				table.insert(garbage, select(i, ...))
			end
		end
		
		baseLibrary.buildFinalClass("BaseModule", BaseModule, KernelObject)
	end
	
	
	--[[
			Kernel modules
	]]
	
	
	local KernelModule = {} do
		
		function KernelModule.new(name, closure)
			local self = setmetatable(BaseModule.new(name, closure), KernelModule)
			
			return self
		end
		
		baseLibrary.buildFinalClass("KernelModule", KernelModule, BaseModule)
	end
	
	local KernelModuleHandler = {} do
		
		function KernelModuleHandler.new()
			local self = setmetatable({}, KernelModuleHandler)
			
			self.Modules = {}
			
			return self
		end
		
		function KernelModuleHandler:LoadModule(name)
			local moduleFile = kernelVariables.KernelModules[name]
			kernelAuditor:Log("KernelModuleHandler:LoadModule:", moduleFile.Path)
			
			local closure = loadstring(moduleFile:Read(), name)
			
			local module = KernelModule.new(name, closure)
			
			module:Run()
			local result = module.Result
			
			self.Modules[name] = result
			
			return result
		end
		
		function KernelModuleHandler:GetModule(name)
			local moduleResult = self.Modules[name]
			
			if moduleResult then
				return unpack(moduleResult)
			end
			
			return unpack(self:LoadModule(name))
		end
		
		baseLibrary.buildFinalSingleton("KernelModuleHandler", KernelModuleHandler, KernelObject)
		
		kernelModuleHandler = KernelModuleHandler.new()
	end
	
	
	--[[
			User modules
	]]
	
	
	local UserModule = {} do
		
		function UserModule.new(helper, name, closure)
			local self = setmetatable(BaseModule.new(name, closure), KernelModule)
			
			self._Helper = helper
			
			return self
		end
		
		function UserModule:Destroy()
			self._Helper:_RemoveModule(self)
		end
		
		baseLibrary.buildFinalClass("UserModule", UserModule, BaseModule)
	end
	
	local UserModuleHelper = {} do
		
		function UserModuleHelper.new(handler, moduleFile)
			local self = setmetatable({}, UserModuleHelper)
			
			self.File = moduleFile
			self.Name = moduleFile.Name
			self.Source = moduleFile:Read()
			self.Hash = syn.crypt.hash(self.Source)
			self.Modules = {}
			
			return self
		end
		
		function UserModuleHelper:Destroy()
			self:DestroyModules()
			userModuleHandler:_RemoveHelper(self)
		end
		
		function UserModuleHelper:CreateModule()
			local closure, error = loadstring(self.Source, self.Name)
			
			assert(closure, error)
			
			local module = UserModule.new(self, self.Name, closure, self.Hash)
			self:_AddModule(module)
			return module
		end
		
		function UserModuleHelper:_RemoveModule(module)
			local activeModules = self.Modules
			table.remove(activeModules, assert(table.find(activeModules, module), "missing module index"))
		end
		
		function UserModuleHelper:_AddModule(module)
			table.insert(self.Modules, module)
		end
		
		function UserModuleHelper:DestroyModules()
			for _, module in ipairs(self.Modules) do
				module:Destroy()
			end
		end
		
		function UserModuleHelper:FindModule(index)
			index = index or 1
			
			baseLibrary.expectType(index, "number")
			
			return self.Modules[index]
		end
		
		function UserModuleHelper:GetModule(asResult, index)
			local module = self:FindModule(index)
			
			if not module then
				module = self:CreateModule()
				if asResult then
					module:Run()
				end
			end
			
			return asResult and unpack(module.Result) or module
		end
		
		baseLibrary.buildFinalClass("UserModuleHelper", UserModuleHelper, KernelObject)
	end
	
	local UserModuleHandler = {} do
		
		function UserModuleHandler.new()
			local self = setmetatable({}, UserModuleHandler)
			
			self.Helpers = {}
			
			return self
		end
		
		function UserModuleHandler:Destroy()
			for _, module in ipairs(self.Helpers) do
				module:Destroy()
			end
		end
		
		function UserModuleHandler:FindModuleFile(name)
			return kernelVariables.UserModules[name]
		end
		
		
		function UserModuleHandler:FindHelper(fileOrNameOrHash)
			for _, helper in ipairs(self.Helpers) do
				if helper.File == fileOrNameOrHash
					or helper.Name == fileOrNameOrHash
					or helper.Hash == fileOrNameOrHash then
					return helper
				end
			end
		end
		
		function UserModuleHandler:GetHelper(moduleFile)
			local helper = self:FindHelper(moduleFile)
			if not helper then
				helper = UserModuleHelper.new(self, moduleFile)
				self:_AddHelper(helper)
			end
			
			return helper
		end
		
		function UserModuleHandler:_AddHelper(module)
			table.insert(self.Helpers, module)
		end
		
		function UserModuleHandler:_RemoveHelper(module)
			local helpers = self.Helpers
			table.remove(helpers, assert(table.find(helpers, module), "invalid helper index"))
		end
		
		
		function UserModuleHandler:NewModule(moduleFileOrString)
			local moduleFile
			
			if type(moduleFileOrString) == "string" then
				moduleFile = self:FindModuleFile(moduleFileOrString)
				baseLibrary.assertf(moduleFile, "unable to find module '%s'", moduleFileOrString)
			end
			
			local helper = self:GetHelper(moduleFile)
			
			local module = helper:CreateModule()
			self:_AddHelper(module)
			
			return module
		end
		
		function UserModuleHandler:LoadModule(nameOrFile)
			local moduleFile
			
			if type(nameOrFile) == "string" then
				moduleFile = self:FindModuleFile(nameOrFile)
				baseLibrary.assertf(moduleFile, "unable to find module '%s'", nameOrFile)
			else
				baseLibrary.expectClass(nameOrFile)
				assert(nameOrFile:IsA(fs.File))
				moduleFile = nameOrFile
			end
			
			kernelAuditor:Log("UserModuleHandler:LoadModule:", moduleFile.Path)
			self:NewModule(moduleFile):Run()
		end
		
		function UserModuleHandler:GetModule(name, getResult)
			local moduleFile = self:FindModuleFile(name)
			local helper = self:GetHelper(moduleFile)
			
			return helper:GetModule(getResult)
		end
		
		-- currently unexposed
		
		function UserModuleHandler:DestroyModulesWithHash(hash)
			baseLibrary.expectType(hash, "string")
			
			local helper = self:FindHelper(hash)
			if helper then
				helper:Destroy()
			end
		end
		
		function UserModuleHandler:GetClearModule(nameOrFile)
			local helper = self:FindHelper(nameOrFile)
			if helper then
				helper:DestroyModules()
			end
			
			self:LoadModule(nameOrFile)
		end
		
		
		baseLibrary.buildFinalSingleton("UserModuleHandler", UserModuleHandler, KernelObject)
	end
	
	userModuleHandler = UserModuleHandler.new()
end


local Kernel = {} do
	
	local function copy(t)
		
		local result = {}
		
		for i, v in pairs(t) do
			if type(v) == "table" then
				result[i] = copy(v)
			else
				result[i] = v
			end
		end
		
		return result
	end
	
	local original = copy(untrustedEnvironment)
	
	local function setupEnvironments()
		
		
		
		-- raw functions
		
		local raw_get_thread_identity = syn.get_thread_identity
		local raw_set_thread_identity = syn.set_thread_identity
		
		local raw_checkcaller = checkcaller
		local raw_hookfunction = hookfunction
		local raw_hookmetamethod = hookmetamethod
		
		-- threads
		
		local getCurrentThread = coroutine.running
		local threads = setmetatable({}, {__mode = "k"})
		
		local function isDuskThread()
			return rawGetThreadIdentity == DUSK_THREAD_IDENTITY
		end
		
		local function newGetThreadIdentity()
			if isDuskThread() then
				return raw_get_thread_identity()
			end
			
			raw_get_thread_identity()
		end
		
		-- must be restored from original thread
		local function newSetThreadIdentity(n)
			if isDuskThread() then
				threads[getCurrentThread()] = true
			end
			
			if n == DUSK_THREAD_IDENTITY and not threads[getCurrentThread()] then return end
			
			raw_set_thread_identity(n)
		end
		
		
		-- hooks
		
		
		local function newhookfunction(target, hook)
			return kernel.HookHandler:HookFunction(target, hook)
		end
		
		local function newhookmetamethod(target, tag, hook, ...)
			if typeof(target) == "Instance" then
				if tag == "__index" then
					return kernel.HookHandler:HookGameIndex(hook)
				elseif tag == "__namecall" then
					return kernel.HookHandler:HookGameNamecall(hook)
				end
			else
				kernelAuditor:Log("unknown hook usage", target, tag, hook)
				return raw_hookmetamethod(target, tag, hook, ...)
			end
		end
		
		-- misc
		
		local function gettenv()
			return trustedEnvironment
		end
		
		local function getutenv()
			return untrustedEnvironment
		end
		
		local function new_getgenv()
			if isDuskThread() then
				return trustedEnvironment
			end
			return untrustedEnvironment
		end
		
		local function setupTrustedEnvironment()
			
			for name, value in pairs(baseLibrary) do
				trustedEnvironment[name] = value
			end
			
			trustedEnvironment.print = print
			trustedEnvironment.warn = warn
			trustedEnvironment.error = error
			
			trustedEnvironment.PatchHandler = patchHandler
			trustedEnvironment.DuskObject = DuskObject
			
			trustedEnvironment.istrusted = true
			trustedEnvironment.gettenv = gettenv
			trustedEnvironment.getutenv = getutenv
			trustedEnvironment.getgenv = new_getgenv
			
			trustedEnvironment.hookmetamethod = raw_hookmetamethod
			trustedEnvironment.hookfunction = raw_hookfunction
			
			trustedEnvironment.isduskthread = isDuskThread
			trustedEnvironment.getthreadidentity = newGetThreadIdentity
			trustedEnvironment.setthreadidentity = newSetThreadIdentity
			trustedEnvironment.checkcaller = raw_checkcaller
			
			-- raw functions
			trustedEnvironment.decompile = decompile
			trustedEnvironment.saveinstance = saveinstance
			trustedEnvironment.loadstring = loadstring
			trustedEnvironment.islclosure = islclosure
			trustedEnvironment.newcclosure = newcclosure
			trustedEnvironment.isnetworkowner = isnetworkowner
			trustedEnvironment.gethiddenproperty = gethiddenproperty
			trustedEnvironment.sethiddenproperty = sethiddenproperty
			trustedEnvironment.setsimulationradius = setsimulationradius
			
			trustedEnvironment.getsenv = getsenv
			trustedEnvironment.getcallingscript = getcallingscript
			trustedEnvironment.getscriptclosure = getscriptclosure
			trustedEnvironment.getscripthash = getscripthash
			
			trustedEnvironment.getrawmetatable = getrawmetatable
			trustedEnvironment.setrawmetatable = setrawmetatable
			trustedEnvironment.setreadonly = setreadonly
			trustedEnvironment.isreadonly = isreadonly
			
			trustedEnvironment.readfile = raw_readfile
			trustedEnvironment.writefile = raw_writefile
			trustedEnvironment.appendfile = raw_appendfile
			trustedEnvironment.listfiles = listfiles
			trustedEnvironment.isfile = isfile
			trustedEnvironment.isfolder = isfolder
			trustedEnvironment.makefolder = makefolder
			trustedEnvironment.delfolder = delfolder
			trustedEnvironment.delfile = delfile
			
			trustedEnvironment.setclipboard = setclipboard
			trustedEnvironment.setfflag = setfflag
			trustedEnvironment.getnamecallmethod = getnamecallmethod
			trustedEnvironment.setnamecallmethod = setnamecallmethod
			trustedEnvironment.getsynasset = getsynasset
			trustedEnvironment.getspecialinfo = getspecialinfo
			trustedEnvironment.messagebox = messagebox
			
			trustedEnvironment.string = string
			trustedEnvironment.table = table
			trustedEnvironment.debug = debug
			trustedEnvironment.bit = bit
			trustedEnvironment.syn = syn
		end
		
		local function patchUntrustedEnvironment()
			
			local function protectedCheckcaller()
				return raw_checkcaller()
			end
			
			local function patchBaseLib()
				untrustedEnvironment.getgenv = newcclosure(new_getgenv)
				untrustedEnvironment.hookmetamethod = newcclosure(newhookmetamethod)
				untrustedEnvironment.hookfunction = newcclosure(newhookfunction)
				untrustedEnvironment.checkcaller = newcclosure(protectedCheckcaller)
			end
			
			local function patchSynLib()
				setreadonly(syn, false)
				syn.get_thread_identity = newcclosure(newGetThreadIdentity)
				syn.set_thread_identity = newcclosure(newSetThreadIdentity)
				setreadonly(syn, true)
			end
			
			patchBaseLib()
			patchSynLib()
		end
		
		setupTrustedEnvironment()
		patchUntrustedEnvironment()
		
		getrawmetatable(duskGlobalEnvironment).__index = trustedEnvironment
	end
	
	local function setupGlobalEnvironment()
		
		if kernelSettings:GetField("ModifyUntrustedEnvironment") then
			
			local function injectEnvironment()
				
				local debugMode = kernelSettings:GetField("DebugModeEnabled")
				local unionWithTrustedEnvironment = kernelSettings:GetField("UnionWithTrustedEnvironment")
				local addBaseLibrary = kernelSettings:GetField("AddBaseLibrary")
				local addKernelReference = kernelSettings:GetField("AddKernelReference")
				local addTrustedEnvironmentReference = kernelSettings:GetField("AddTrustedEnvironmentReference")
				
				local function setfield(t, k, v)
					if debugMode or not rawget(t, k) then
						rawset(t, k, v)
					else
						baseLibrary.warnf("namespace conflict: %s already exists in global environment", k)
					end
				end
				
				if unionWithTrustedEnvironment then
					for i, v in pairs(trustedEnvironment) do
						setfield(untrustedEnvironment, i, v)
					end
				else
					for i, v in pairs(baseLibrary) do
						setfield(untrustedEnvironment, i, v)
					end
					
					if addKernelReference then
						untrustedEnvironment.kernel = kernel
					end
					
					if addTrustedEnvironmentReference then
						trustedEnvironment.dusk = addTrustedEnvironmentReference
					end
				end
				
			end
			
			local function clearEnvironment()
				
				for i, v in pairs(trustedEnvironment) do
					if rawget(untrustedEnvironment, i) == v then
						rawset(untrustedEnvironment, i, nil)
					end
				end
				
				if rawget(untrustedEnvironment, "dusk") == trustedEnvironment then
					rawset(untrustedEnvironment, "dusk", nil)
				end
			end
			
			patchHandler:NewPatch(injectEnvironment, clearEnvironment):Run()
		end
	end
	
	
	function Kernel.new()
		local self = setmetatable({}, Kernel)
		
		kernel = self
		trustedEnvironment.kernel = self
		
		self.Settings = kernelSettings
		self.PatchHandler = patchHandler
		
		libraryHandler:AddLibrary(fs, "fs")
		libraryHandler:AddLibrary(baseLibrary, "base")
		
		setupEnvironments()
		
		self.HookHandler = self:_LoadKernelFile(HOOK_HANDLER_PATH, "HookHandler")
		kernelModuleHandler:LoadModule("NetworkGuard")
		--kernelModuleHandler:LoadModule("CallStackGuard") -- getfenv conflict
		
		libraryHandler:InitLibrary("cache")
		libraryHandler:InitLibrary("input")
		
		if kernelSettings:GetField("LoadUserComponents") then
			self:_LoadKernelFile(USER_PATH, "user")
		end
		
		setupGlobalEnvironment()
		
		table.freeze(self)
		
		return self
	end
	
	function Kernel:Destroy()
		patchHandler:Destroy()
		self.HookHandler:Destroy()
	end
	
	function Kernel:Log(...)
		local message = ""
		
		local size = select("#", ...)
		for i = 1, size do
			message ..= tostring(select(i, ...))
			if i < size then
				message ..= " "
			end
		end
		
		kernelAuditor:Log(message)
	end
	
	function Kernel:_LoadKernelFile(path, name)
		kernelAuditor:Log("LoadKernelFile:", name)
		
		local closure = assert(loadfile(path, name))
		baseLibrary.assertf(closure, "unable to create %s closure", name)
		
		return closure(self)
	end
	
	function Kernel:GetLibrary(name)
		baseLibrary.expectType(name, "string")
		return libraryHandler:GetLibrary(name)
	end
	
	function Kernel:LoadModule(name)
		baseLibrary.expectType(name, "string")
		return userModuleHandler:LoadModule(name)
	end
	
	function Kernel:GetModule(name, getResult)
		getResult = getResult == nil and true
		baseLibrary.expectType(name, "string")
		baseLibrary.expectType(getResult, "boolean")
		return userModuleHandler:GetModule(name, getResult)
	end
	
	function Kernel:GetKernelModule(name)
		baseLibrary.expectType(name, "string")
		return kernelModuleHandler:GetModule(name)
	end
	
	function Kernel:GetEnvironment()
		return trustedEnvironment
	end
	
	function Kernel:GetMainBaseClass()
		return DuskObject
	end
	
	baseLibrary.buildFinalSingleton("Kernel", Kernel, KernelObject)
end

kernel = Kernel.new()

warn("dusk loaded")