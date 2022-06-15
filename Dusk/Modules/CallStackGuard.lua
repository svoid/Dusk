local CallStackGuard = {} do
	
	function CallStackGuard.new()
		local self = setmetatable({}, CallStackGuard)
		
		self.Methods = {}
		
		
		local robloxPseudoEnvironment = setmetatable({}, {
			__index = getrenv(),
			__metatable = "The metatable is locked"
		})
		
		self:RetrieveMethod(getfenv, "getfenv", function(raw, levelOrFunction)
			local vtype = type(levelOrFunction)
			
			local result = raw(levelOrFunction)
			
			if vtype == "number" then
				
				while isDuskFunction(result) do
					levelOrFunction += 1
					result = raw(levelOrFunction)
				end
				
				return result
			elseif vtype == "function" then
				
				if isDuskFunction(result) then
					return robloxPseudoEnvironment
				end
				
				return result
			end
		end)
		
		local dummyFunctions = setmetatable({}, {__mode = "k"})
		
		local function getDummyFunciton(real)
			local dummy = dummyFunctions[real]
			if dummy then
				return dummy
			end
			
			local dummy = function()end
			
			setfenv(dummy, robloxPseudoEnvironment)
			
			dummyFunctions[real] = dummy
			
			return dummy
		end
		
		self:RetrieveMethod(debug.info, "debug.info", function(raw, ...)
			local r0, r1, r2, r3, r4, r5 = raw(...)
			
			if type(r0) == "function" and isDuskFunction(r0) then
				r0 = getDummyFunciton(r0)
				return r0, r1, r2, r3, r4, r5
			elseif type(r1) == "function" and isDuskFunction(r1) then
				r1 = getDummyFunciton(r1)
				return r0, r1, r2, r3, r4, r5
			elseif type(r2) == "function" and isDuskFunction(r2) then
				r2 = getDummyFunciton(r2)
				return r0, r1, r2, r3, r4, r5
			elseif type(r3) == "function" and isDuskFunction(r3) then
				r3 = getDummyFunciton(r3)
				return r0, r1, r2, r3, r4, r5
			elseif type(r4) == "function" and isDuskFunction(r4) then
				r4 = getDummyFunciton(r4)
				return r0, r1, r2, r3, r4, r5
			elseif type(r5) == "function" and isDuskFunction(r5) then
				r5 = getDummyFunciton(r5)
				return r0, r1, r2, r3, r4, r5
			end
		end)
		
		return self
	end
	
	function CallStackGuard:RetrieveMethod(func, name, handler)
		local raw
		raw = hookfunction(func, function(...)
			return handler(raw, ...)
		end)
		
		self.Methods[name] = raw
	end
	
	buildFinalSingleton("CallStackGuard", CallStackGuard, DuskObject)
end

kernel.CallStackGuard = CallStackGuard.new()