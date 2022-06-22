local initData = ...

local rawSettings = initData.RawSettings
local baseLibrary = initData.BaseLibrary

local expectType = baseLibrary.expectType
local expectClass = baseLibrary.expectClass

local originals = {
	readfile = readfile,
	writefile = writefile,
	appendfile = appendfile,
	delfile = delfile,
	syn_io_read = syn_io_read,
	syn_io_append = syn_io_append,
	syn_io_delfile = syn_io_delfile,
	
	makefolder = makefolder,
	delfolder = delfolder,
	listfiles = listfiles,
	syn_io_makefolder = syn_io_makefolder,
	syn_io_delfolder = syn_io_delfolder,
	syn_io_listdir = syn_io_listdir,
	
	isfile = isfile,
	isfolder = isfolder,
	syn_io_isfile = syn_io_isfile,
	syn_io_isfolder = syn_io_isfolder,
}

local OSInstance = {} do
	
	function OSInstance.new(path)
		local self = setmetatable({}, OSInstance)
		
		self.Path = path
		self.Parent = nil
		
		return self
	end
	
	function OSInstance:DesyncForParent()
		local parent = self.Parent
		if parent then
			local parentChildren = parent.Children
			table.remove(parentChildren, assert(table.find(parentChildren, self), "invalid object index as child"))
		end
	end
	
	function OSInstance:Sync()
		
	end
	
	baseLibrary.buildFinalClass("OSInstance", OSInstance, initData.DuskObject)
end

local File = {} do
	
	function File.new(path)
		local self = setmetatable(OSInstance.new(path), File)
		
		self.FullName = string.gsub(self.Path, "[^\\]+\\", "")
		self.Name = string.gsub(self.FullName, "%.%a+$", "")
		self.Extension = string.gsub(self.FullName, ".+%.", "")
		
		return self
	end
	
	function File:Destroy()
		originals.delfile(self.Path)
	end
	
	function File:Desync()
		self:DesyncForParent()
	end
	
	function File:Read()
		return originals.readfile(self.Path)
	end
	
	function File:Append(content)
		expectType(content, "string")
		return originals.readfile(self.Path, content)
	end
	
	function File:Write(content)
		return originals.readfile(self.Path, content)
	end
	
	baseLibrary.buildFinalClass("File", File, OSInstance)
end

local Folder = {} do
	
	function Folder.new(path)
		local self = setmetatable(OSInstance.new(path), Folder)
		
		self.FullName = path
		self.Name = string.gsub(path, "[^\\]+\\", "")
		
		self.Children = {}
		
		return self
	end
	
	function Folder:Destroy()
		originals.delfolder(self.Path)
		self:Desync()
	end
	
	local function checkChildExists(children, path, type)
		for _, child in ipairs(children) do
			if child.Path == path then
				if not child:IsA(type) then
					child:Desync()
				else
					return child
				end
			end
		end
	end
	
	function Folder:Desync()
		self:DesyncForParent()
		
		for _, child in ipairs(self:GetChildren()) do
			child:Desync()
		end
	end
	
	function Folder:SyncFolder(path)
		expectType(path, "string")
		local folder = Folder.new(path)
		folder.Parent = self
		table.insert(self.Children, folder)
		folder:Sync()
		return folder
	end
	
	function Folder:SyncFile(path)
		expectType(path, "string")
		local file = File.new(path)
		file.Parent = self
		table.insert(self.Children, file)
		file:Sync()
		return file
	end
	
	function Folder:NewFolder(name)
		expectType(name, "string")
		local path = self.Path .. "\\" .. name
		originals.makefolder(path)
		return self:SyncFolder(path)
	end
	
	function Folder:NewFile(name, content)
		expectType(name, "string")
		expectType(content, "string")
		local path = self.Path .. "\\" .. name
		originals.writefile(path, content or "")
		return self:SyncFile(path)
	end
	
	function Folder:GetFile(name)
		expectType(name, "string")
		
		local file = self[name]
		
		if not file or not file:IsA("File") then
			file = self:NewFile(name)
		end
		
		return file
	end
	
	function Folder:GetFolder(name)
		expectType(name, "string")
		
		local folder = self[name]
		
		if not folder or not folder:IsA("Folder") then
			folder = self:NewFolder(name)
		end
		
		return folder
	end
	
	function Folder:GetChildren()
		local result = {}
		
		for i, instance in ipairs(self.Children) do
			result[i] = instance
		end
		
		return result
	end
	
	local vftable
	
	local override = {}
	
	function override:Sync()
		local currentChildren = self:GetChildren()
		
		for _, path in ipairs(originals.listfiles(self.Path)) do
			
			if originals.isfile(path) then
				
				local file = checkChildExists(currentChildren, path, "File")
				if not file then
					self:SyncFile(path)
				else
					table.remove(currentChildren, assert(table.find(currentChildren, file), "invalid file index as child"))
				end
			elseif originals.isfolder(path) then
				local folder = checkChildExists(currentChildren, path, "Folder")
				if not folder then
					self:SyncFolder(path)
				else
					table.remove(currentChildren, assert(table.find(currentChildren, folder), "invalid folder index as child"))
				end
			else
				warn("invalid path on Folder:Sync", path)
			end
		end
		
		for _, child in ipairs(currentChildren) do
			child:Desync()
		end
	end
	
	function override:__index(index)
		local member = vftable[index]
		if member then
			return member
		end
		
		for _, child in ipairs(self.Children) do
			if child.Name == index or child.FullName == index then
				return child
			end
		end
	end
	
	vftable = baseLibrary.buildFinalClassOverride("Folder", Folder, override, OSInstance)
end

local root = Folder.new("")
root:Sync()
initData.RootFolder = root

if rawSettings.FileSystemSandbox then
	local untrustedEnvironment = initData.UntrustedEnvironment
	
	local function override()
		local SANDBOX_PATH = rawSettings.SandboxPath
		
		-- TODO: use instance with getFolderHandler
		
		pcall(function()
			makefolder(SANDBOX_PATH)
		end)
		
		for name, original in pairs(originals) do
			
			local function wrapped(path, ...)
				expectType(path, "string")
				path = SANDBOX_PATH .. "/" .. path
				
				return original(path, ...)
			end
			
			local new = newcclosure(wrapped)
			rawset(untrustedEnvironment, name, new)
		end
	end
	
	local function repair()
		for name, original in pairs(originals) do
			rawset(untrustedEnvironment, name, original)
		end
	end
	
	initData.PatchHandler:NewPatch(override, repair):Run()
end


local OBuffer = {} do
	
	function OBuffer.new(file)
		expectClass(file, "File")
		
		local self = setmetatable({}, OBuffer)
		
		self.File = file
		
		self.Buffer = ""
		self.Size = 0
		self.MaxSize = 5000
		
		self.LastWrite = 0
		self.Writes = 0
		
		self.DelayTime = 3
		return self
	end
	
	function OBuffer:Destroy()
		if self.Size > 0 then
			self:Append()
		end
	end
	
	function OBuffer:Append()
		self.File:Append(self.Buffer)
		self.Buffer = ""
		self.Size = 0
	end
	
	if rawSettings.FastFileBuffers then
		function OBuffer:Write(string)
			self.Writes += 1
			
			local newBuffer = self.Buffer .. string
			local newSize = #string
			
			if newSize >= self.MaxSize then
				self.File:Append(newBuffer)
				self.Buffer = ""
				self.Size = 0
				return
			end
			
			self.Buffer = newBuffer
			self.Size = newSize
			
			local thisWrites = self.Writes
			task.wait(self.DelayTime)
			if thisWrites == self.Writes then
				self.File:Append(newBuffer)
				self.Buffer = ""
				self.Size = 0
			end
		end
	else
		function OBuffer:Write(string)
			expectType(string, "string")
			self.Writes += 1
			
			self.Buffer ..= string
			self.Size = #string
			if self.Size >= self.MaxSize then
				self:Append()
				return
			end
			
			local thisWrites = self.Writes
			task.wait(self.DelayTime)
			if thisWrites == self.Writes then
				self:Append()
			end
		end
	end
	
	baseLibrary.buildFinalClass("OBuffer", OBuffer)
end

local IBuffer = {} do
	
	function IBuffer.new(fileOrString)
		local buffer
		if type(fileOrString) == "string" then
			buffer = fileOrString
		else
			buffer = expectClass(fileOrString, "File"):Read()
		end
		
		local self = setmetatable({}, IBuffer)
		
		self.Buffer = buffer
		self.Position = 0
		
		return self
	end
	
	function IBuffer:Read(size)
		size = size or 1
		
		local startPosition = self.Position
		local endPosition = startPosition + size
		
		local result = self.Buffer:sub(startPosition, endPosition)
		
		self.Position = endPosition
		
		return result
	end
	
	baseLibrary.buildFinalClass("IBuffer", IBuffer)
end



local function getFileHandler(path)
	
end

local function getFolderHandler(path)
	
end

local lib = {}

lib.getFileHandler = getFileHandler
lib.getFolderHandler = getFolderHandler
lib.OBuffer = OBuffer
lib.IBuffer = IBuffer

return baseLibrary.protectLib(lib)