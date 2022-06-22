local function log(...)
	kernel:Log(...)
	print(...)
end


local TaskAction = {
	Pass = "Pass",
	Hold = "Hold",
	Drop = "Drop",
	Kill = "Kill"
}

local DomainHandlerResult = {
	Unhandled = "Unhandled",
	PassAndResolve = "PassAndResolve",
	Return = "Return",
}



local NetworkTask = {} do
	
	function NetworkTask.new(name, url, domain, networkMethod, instanceOrOptions, ...)
		local self = setmetatable({}, NetworkTask)
		
		self.Url = url
		self.Domain = domain
		
		self.Name = name
		
		self.NetworkMethod = networkMethod
		self.InstanceOrOptions = instanceOrOptions
		self.Thread = coroutine.running()
		self.AditionalArguments = {...}
		self.When = os.time()
		
		self.WasDropped = false
		self.IsYielded = false
		self.OriginalResult = nil
		self.ReturnedResult = nil
		
		self.CanYield = true
		
		return self
	end
	
	function NetworkTask:Destroy()
		self.CanYield = false
		if self.IsYielded then
			log("Dropping due to destructor call", self.Url)
			task.defer(self.Thread, self:Drop())
		end
		
		self.Thread = nil
		self.NetworkMethod = nil
		self.InstanceOrOptions = nil
		table.clear(self.AditionalArguments)
	end
	
	function NetworkTask:ResolveRequest(action)
		log("ResolveRequest", self.Name, action, self.Url)
		local result
		
		if action == TaskAction.Pass then
			result = self:Pass(self.NetworkMethod.RawClosure, self.InstanceOrOptions, unpack(self.AditionalArguments))
		elseif action == TaskAction.Hold then
			result = self:Hold()
		elseif action == TaskAction.Drop then
			result = self:Drop()
		elseif action == TaskAction.Kill then
			result = self:Kill()
		end
		
		self.OriginalResult = result
		return result
	end
	
	function NetworkTask:ResolveResult(action, originalResult)
		if self.WasDropped then
			return originalResult
		end
		
		log("ResolveResult", self.Name, action, self.Url)
		
		local result
		
		if action == TaskAction.Pass then
			result = originalResult
		elseif action == TaskAction.Hold then
			result = {self:Hold()}
		elseif action == TaskAction.Drop then
			result = {self:Drop()}
		elseif action == TaskAction.Kill then
			result = {self:Kill()}
		end
		
		self.ReturnedResult = result
		return result
	end
	
	function NetworkTask:Pass(rawClosure, instanceOrOptions, ...)
		return rawClosure(instanceOrOptions, ...)
	end
	
	function NetworkTask:Hold()
		if not self.CanYield then
			log("Canceled hold and dropped due to destructor call", self.Url)
			return self:Drop()
		end
		
		self.IsYielded = true
		local result = {coroutine.yield()}
		self.IsYielded = false
		return unpack(result)
	end
	
	function NetworkTask:Drop()
		self.WasDropped = true
		return ""
	end
	
	function NetworkTask:Kill()
		error("")
	end
	
	finalizeClass("NetworkTask", NetworkTask, DuskObject)
end

local NetworkMethod = {} do
	
	function NetworkMethod.new(rawClosure, handler, name)
		local self = setmetatable({}, NetworkMethod)
		
		self.RawClosure = rawClosure
		self.Handler = handler
		self.Name = name
		
		self.BlockAllRequests = true
		self.HoldAllRequests = false
		
		self.DomainHandlers = {}
		
		self.DomainsWhitelist = {
			"githubusercontent.com",
			"github.com",
			"github.io",
			"pastebin.com"
		}
		
		self.WhitelistAction = TaskAction.Pass
		self.WhitelistResultAction = TaskAction.Pass
		
		self.DomainsBlacklist = {}
		self.BlacklistAction = TaskAction.Drop
		self.BlacklistResultAction = TaskAction.Pass
		
		self.NotInListAction = TaskAction.Drop
		self.NotInListResultAction = TaskAction.Pass
		
		return self
	end
	
	function NetworkMethod:SetDomainHandler(domain, handler)
		expectType(domain, "string")
		expectType(handler, "function")
		
		self.DomainHandlers[domain] = handler
	end
	
	
	function NetworkMethod:GetDomainHandler(domain)
		return self.DomainHandlers[domain]
	end
	
	finalizeClass("NetworkMethod", NetworkMethod, DuskObject)
end



local NetworkGuard = {} do
	
	NetworkGuard.TaskAction = TaskAction
	NetworkGuard.DomainHandlerResult = DomainHandlerResult
	
	local networkGuard
	
	local function resolveTask(task, networkMethod, domain)
		local domainHandlerResult = DomainHandlerResult.Unhandled
		local domainHandler = networkMethod:GetDomainHandler(domain)
		
		if domainHandler then
			local result = {domainHandler(task)}
			domainHandlerResult = result[1] or domainHandlerResult
			
			if domainHandlerResult == DomainHandlerResult.Return then
				return unpack(result, 2)
			elseif domainHandlerResult == DomainHandlerResult.PassAndResolve then
				local result = {task:ResolveRequest(TaskAction.Pass)}
				return unpack(task:ResolveResult(networkMethod.Pass, result))
			end
		end
		
		if table.find(networkMethod.DomainsBlacklist, domain) then
			local result = {task:ResolveRequest(networkMethod.BlacklistAction)}
			return unpack(task:ResolveResult(networkMethod.BlacklistResultAction, result))
		end
		
		if table.find(networkMethod.DomainsWhitelist, domain) then
			local result = {task:ResolveRequest(networkMethod.WhitelistAction)}
			return unpack(task:ResolveResult(networkMethod.WhitelistResultAction, result))
		end
		
		local result = {task:ResolveRequest(networkMethod.NotInListAction)}
		return unpack(task:ResolveResult(networkMethod.NotInListResultAction, result))
		
	end
	
	local smatch = string.match
	local function extractDomain(url)
		if url then
			return smatch(url, "[%w%.]*%.(%w+%.%w+)") or smatch(url, "%w+%.%w+")
		end
	end
	
	
	
	local function httpHandler(networkMethod, instance, url, ...)
		local name = networkMethod.Name
		local domain = extractDomain(url)
		
		local task = networkGuard:NewTask(name, url, domain, networkMethod, instance, url, ...)
		
		return resolveTask(task, networkMethod, domain)
	end
	
	local function requestHandler(networkMethod, options, ...)
		local name = networkMethod.Name
		local url = rawget(options, "Url")
		local domain = extractDomain(url)
		
		local task = networkGuard:NewTask(name, url, domain, networkMethod, options, ...)
		
		return resolveTask(task, networkMethod, domain)
	end
	
	local function websocketHandler(networkMethod, url, ...)
		local name = networkMethod.Name
		local domain = extractDomain(url)
		
		warn("websocketHandler", url)
		local task = networkGuard:NewTask(name, url, domain, networkMethod, url, ...)
		
		return resolveTask(task, networkMethod, domain)
	end
	
	local function setMethod(name, networkMethod)
		networkGuard.Methods[name] = networkMethod
	end
	
	local function protectAsInstanceMethod(instance, methodName, handler)
		local networkMethod
		local rawClosure = instance[methodName]
		
		local newHttpMethod = function(instance, ...)
			local result = {handler(networkMethod, instance, ...)}
			return unpack(result)
		end
		
		local protected = newcclosure(newHttpMethod)
		
		kernel.HookHandler:HookGameIndex(methodName, instance, function(instance, name)
			return true, protected
		end)
		
		kernel.HookHandler:HookGameNamecall(methodName, instance, function(instance, name, ...)
			return true, newHttpMethod(instance, ...)
		end)
		
		networkMethod = NetworkMethod.new(rawClosure, handler, methodName)
		
		setMethod(methodName, networkMethod)
	end
	
	local function protectAsFunction(closure, name, handler)			
		local networkMethod
		local rawClosure
		
		rawClosure = hookfunction(closure, function(...)
			warn(name)
			warne(...)
			local result = {handler(networkMethod, ...)}
			return unpack(result)
		end)
		
		networkMethod = NetworkMethod.new(rawClosure, handler, name)
		
		setMethod(name, networkMethod)
	end
	
	
	
	function NetworkGuard.new()
		local self = setmetatable({}, NetworkGuard)
		
		networkGuard = self
		
		self.History = {}
		self.MaxLogHistory = 10
		
		self.Methods = {}
		
		protectAsInstanceMethod(game, "HttpGet", httpHandler)
		protectAsInstanceMethod(game, "HttpGetAsync", httpHandler)
		protectAsInstanceMethod(game, "HttpPost", httpHandler)
		protectAsInstanceMethod(game, "HttpPostAsync", httpHandler)
		
		protectAsFunction(syn.websocket.connect, "websocket", websocketHandler)
		
		protectAsFunction(syn.request, "request", requestHandler)
		
		protectAsInstanceMethod = nil
		protectAsFunction = nil
		
		return self
	end
	
	function NetworkGuard:GetMethod(name)
		return self.Methods[name]
	end
	
	function NetworkGuard:NewTask(name, url, domain, ...)
		local task = NetworkTask.new(name, url, domain, ...)
		local history = self.History
		
		local maxLogHistory = self.MaxLogHistory
		
		local lastTask = history[maxLogHistory]
		if lastTask then
			lastTask:Destroy()
			table.remove(history, maxLogHistory)
		end
		
		table.insert(history, 1, task)
		
		return task
	end
	
	buildFinalSingleton("NetworkGuard", NetworkGuard, DuskObject)
end

return NetworkGuard.new()