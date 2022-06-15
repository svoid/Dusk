local KeyCodeSequence = {} do
	
	function KeyCodeSequence.new(...)
		local self = setmetatable({}, KeyCodeSequence)
		
		self.Sequence = {...}
		
		return self
	end
	
	local override = {}
	
	function override:__tostring()
		local result = ""
		
		local sequence = self.Sequence
		
		if #sequence > 0 then
			result ..= sequence[1].Name
			for _, keyCode in next, sequence, 1 do
				result ..= "+" .. keyCode.Name
			end
		end
		
		return result
	end
	
	buildFinalClassOverride("KeyCodeSequence", KeyCodeSequence, override, DuskObject)
end

local Binding = {} do
	
	function Binding.new(sequence, func, name)
		local self = setmetatable({}, Binding)
		
		if sequence == nil then
			sequence = KeyCodeSequence.new()
		else
			expectClassType(sequence, "KeyCodeSequence")
		end
		
		if func ~= nil then
			expectType(func, "function")
		end
		
		self.KeyCodeSequence = sequence
		self.Function = func
		self.Name = name or "unnamed"
		
		return self
	end
	
	function Binding:Call(...)
		self.Function(...)
	end
	
	function Binding:IsEqualSequence(sequence)
		local thisSequence = self.KeyCodeSequence.Sequence
		
		local size = #thisSequence
		if size == 0 or size ~= #sequence  then
			return false
		end
		
		for i, keyCode in ipairs(sequence) do
			if thisSequence[i] ~= sequence[i] then
				return false
			end
		end
		
		return true
	end
	
	local override = {}
	
	function override:__tostring()
		local sequence = tostring(self.KeyCodeSequence)
		
		return string.format("{%s: [%s]}", self.Name, sequence)
	end
	
	buildFinalClassOverride("Binding", Binding, override, DuskObject)
end


local function toBinding(...)
	
	local name
	local func
	local keyCodes = {}
	
	for i = 1, select("#", ...) do
		local arg = select(i, ...)
		
		local vtype = typeof(arg)
		if vtype == "function" then
			func = arg
		elseif vtype == "string" then
			name = arg
		elseif vtype == "EnumItem" then
			if arg.EnumType ~= Enum.KeyCode then
				errorf("EnumItem has invalid EnumType ('%s'), expected KeyCode", tostring(arg.EnumType))
			end
			
			table.insert(keyCodes, arg)
		elseif isClassType(arg, "Binding") then
			return arg
		else
			errorf("unable to convert value of type '%s' to Binding", vtype)
		end
	end
	
	local sequence = KeyCodeSequence.new(unpack(keyCodes))
	
	return Binding.new(sequence, func, name)
end


local HotkeyGroup = {} do
	
	function HotkeyGroup.new(handler)
		local self = setmetatable({}, HotkeyGroup)
		
		self.Bindings = {}
		self._HotkeysHandler = handler
		self.Enabled = false
		
		return self
	end
	
	function HotkeyGroup:Destroy()
		self:Disable()
	end
	
	function HotkeyGroup:Enable()
		if self.Enabled then return end
		self.Enabled = true
		self._HotkeysHandler:_EnableGroup(self)
	end
	
	function HotkeyGroup:Disable()
		if not self.Enabled then return end
		self.Enabled = false
		self._HotkeysHandler:_DisableGroup(self)
	end
	
	function HotkeyGroup:NewBinding(...)
		local binding = toBinding(...)
		table.insert(self.Bindings, binding)
	end
	
	function HotkeyGroup:ApplyQueue(queue)
		for _, binding in ipairs(self.Bindings) do
			if binding:IsEqualSequence(queue) then
				binding:Call()
				return true
			end
		end
		
		return false
	end
	
	buildFinalClass("HotkeyGroup", HotkeyGroup, DuskObject)
end


local HotkeysHandler = {} do
	
	function HotkeysHandler.new()
		local self = setmetatable({}, HotkeysHandler)
		
		self.ActiveGroups = {}
		self.Groups = {}
		self.Queue = {}
		
		self.InputBeganConnection = game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			
			self:AddKeyCode(input.KeyCode)
		end)
		
		self.InputEndedConnection = game:GetService("UserInputService").InputEnded:Connect(function(input, gameProcessed)
			if gameProcessed then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			
			self:RemoveKeyCode(input.KeyCode)
		end)
		
		return self
	end
	
	function HotkeysHandler:Destroy()
		for _, group in ipairs(self.Groups) do
			group:Destroy()
		end
		
		self.InputBeganConnection:Disconnect()
		self.InputBeganConnection = nil
		
		self.InputEndedConnection:Disconnect()
		self.InputEndedConnection = nil
	end
	
	function HotkeysHandler:AddKeyCode(keyCode)
		table.insert(self.Queue, keyCode)
		
		for _, group in ipairs(self.ActiveGroups) do
			local success = group:ApplyQueue(self.Queue)
			
			if success then
				self:ResetInput()
				break
			end
		end
	end
	
	function HotkeysHandler:RemoveKeyCode(toRemove)
		local queue = self.Queue
		
		for i, keyCode in ipairs(queue) do
			if keyCode == toRemove then
				table.remove(queue, i)
				break
			end
		end
	end
	
	function HotkeysHandler:ResetInput()
		table.clear(self.Queue)
	end
	
	function HotkeysHandler:_EnableGroup(object)
		table.insert(self.ActiveGroups, object)
	end
	
	function HotkeysHandler:_DisableGroup(object)
		local activeCGroups = self.ActiveGroups
		table.remove(activeCGroups, table.find(activeCGroups, object))
	end
	
	function HotkeysHandler:NewGroup()
		local object = HotkeyGroup.new(self)
		table.insert(self.Groups, object)
		return object
	end
	
	function HotkeysHandler:_RemoveGroup(object)
		local Groups = self.Groups
		table.remove(Groups, table.find(Groups, object))
	end
	
	buildFinalClass("HotkeysHandler", HotkeysHandler, DuskObject)
end

local library = {}

library.toBinding = toBinding

library.KeyCodeSequence = KeyCodeSequence
library.Binding = Binding
library.HotkeyGroup = HotkeyGroup
library.HotkeysHandler = HotkeysHandler

return protectLib(library)