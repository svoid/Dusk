-- Hook:IsTargetedTo should stay inlined in hook handlers due to optimization reasons

local Hook = {} do
	
	function Hook.new(handler)
		local self = setmetatable({}, Hook)
		
		self.Handler = handler
		
		return self
	end
	
	buildFinalClass("Hook", Hook, DuskObject)
end

local HookType = {
	Name = "Name",
	Instance = "Instance",
	Both = "Both"
}

local function getHookType(name, instance)
	if name then
		if instance then
			return HookType.Both
		else
			return HookType.Name
		end
	elseif instance then
		return HookType.Instance
	end
end

local NamecallHook = {} do
	
	function NamecallHook.new(methodName, instance, handler)
		local self = setmetatable(Hook.new(handler), Hook)
		
		self.MethodName = methodName
		self.Instance = instance
		self.Type = getHookType(methodName, instance)
		
		return self
	end
	
	function NamecallHook:IsTargetedTo(name, instance)
		return self.MethodName == name
			and self.Instance == instance
	end
	
	buildFinalClass("NamecallHook", NamecallHook, Hook)
end

local IndexHook = {} do
	
	function IndexHook.new(fieldName, instance, handler)
		local self = setmetatable(Hook.new(handler), Hook)
		
		self.FieldName = fieldName
		self.Instance = instance
		self.Type = getHookType(fieldName, instance)
		
		return self
	end
	
	function IndexHook:IsTargetedTo(name, instance)
		return self.FieldName == name
			and self.Instance == instance
	end
	
	buildFinalClass("IndexHook", IndexHook, Hook)
end

local TargetedHookHandler = {} do
	
	function TargetedHookHandler.new()
		local self = setmetatable({}, TargetedHookHandler)
		
		self.Hooks = {}
		
		return self
	end
	
	function TargetedHookHandler:GetHook(name, instance)
		for _, hook in ipairs(self.Hooks) do
			if hook:IsTargetedTo(name, instance) then
				return hook
			end
		end
	end
	
	function TargetedHookHandler:GetHooks(name, instance)
		local result = {}
		for _, hook in ipairs(self.Hooks) do
			if hook:IsTargetedTo(name, instance) then
				table.insert(result, hook)
			end
		end
		return result
	end
	
	function TargetedHookHandler:AddHook(hook)
		table.insert(self.Hooks, 1, hook)
	end
	
	function TargetedHookHandler:_NewHook_Handler(name, handler)
		expectType(handler, "function")
		
		return self.HookConstructor(name, nil, handler)
	end
	
	function TargetedHookHandler:_NewHook_Instance_Handler(name, instance, handler)
		expectRBXType(instance, "Instance")
		expectType(handler, "function")
		
		return self.HookConstructor(name, instance, handler)
	end
	
	function TargetedHookHandler:NewHook(name, instanceOrFunction1, instanceOrFunction2)
		expectType(name, "string")
		
		local instance
		local handler
		
		if type(instanceOrFunction1) == "function" then
			handler = instanceOrFunction1
		else
			instance = expectRBXType(instanceOrFunction1, "Instance")
			handler = expectType(instanceOrFunction2, "function")
		end
		
		local hook = self.HookConstructor(name, instance, handler)
		
		self:AddHook(hook)
		
		return hook
	end
	
	buildFinalClass("TargetedHookHandler", TargetedHookHandler, DuskObject)
end

local GameIndexHookHandler = {} do
	
	function GameIndexHookHandler.new()
		local self = setmetatable(TargetedHookHandler.new(), GameIndexHookHandler)
		
		self.HookConstructor = IndexHook.new
		
		local hooks = self.Hooks
		local rawindex
		
		rawindex = hookmetamethod(game, "__index", function(instance, fieldName)
			
			for _, hook in next, hooks do
				
				if hook.Type == HookType.Both then
					if not (hook.FieldName == fieldName and hook.Instance == instance) then
						continue
					end
				else
					if not (hook.FieldName == fieldName or hook.Instance == instance) then
						continue
					end
				end
				
				local pass, result = hook.Handler(instance, fieldName)
				if pass then
					return result
				end
			end
			
			return rawindex(instance, fieldName)
		end)
		
		self.RawNamecall = rawindex
		
		return self
	end
	
	buildFinalSingleton("GameIndexHookHandler", GameIndexHookHandler, TargetedHookHandler)
end

local GameNamecallHookHandler = {} do
	
	function GameNamecallHookHandler.new()
		local self = setmetatable(TargetedHookHandler.new(), GameNamecallHookHandler)
		
		self.HookConstructor = NamecallHook.new
		
		local hooks = self.Hooks
		local rawnamecall
		
		rawnamecall = hookmetamethod(game, "__namecall", function(...)
			local instance = ...
			local methodName = getnamecallmethod()
			
			
			for _, hook in next, hooks do
				
				
				if hook.Type == HookType.Both then
					if not (hook.MethodName == methodName and hook.Instance == instance) then
						continue
					end
				else
					if not (hook.MethodName == methodName or hook.Instance == instance) then
						continue
					end
				end
				
				local result = {hook.Handler(instance, methodName, ...)}
				
				if result[1] then
					return unpack(result, 2)
				end
			end
			
			return rawnamecall(...)
		end)
		
		self.RawNamecall = rawnamecall
		
		return self
	end
	
	buildFinalSingleton("GameNamecallHookHandler", GameNamecallHookHandler, TargetedHookHandler)
end

local HookHandler = {} do
	
	function HookHandler.new()
		local self = setmetatable({}, HookHandler)
		
		self.GameIndexHookHandler = GameIndexHookHandler.new()
		self.GameNamecallHookHandler = GameNamecallHookHandler.new()
		
		return self
	end
	
	function HookHandler:HookFunciton(target, hook)
		return hookfunction(target, hook)
	end
	
	function HookHandler:HookGameIndex(name, instance, handler)
		self.GameIndexHookHandler:NewHook(name, instance, handler)
	end
	
	function HookHandler:HookGameNamecall(name, instance, handler)
		self.GameNamecallHookHandler:NewHook(name, instance, handler)
	end
	
	buildFinalSingleton("HookHandler", HookHandler, DuskObject)
end

return HookHandler.new()