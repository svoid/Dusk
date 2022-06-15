local function log(...)
	print(...)
end

local function cookie()
	return "\240\159\141\170"
end

local function generateIp()
	return string.format("%d.%d.%d.%d",
		math.random(0, 255),
		math.random(0, 255),
		math.random(0, 255),
		math.random(0, 255)
	)
end

local gifs = {
	"https://cdn.discordapp.com/attachments/427901354393206814/517544450944401456/th.gif",
	"https://tenor.com/view/minions-family-guy-minion-griffin-annoying-orange-youtube-gif-19931672",
	"https://tenor.com/view/dog-meme-edit-shitpost-silence-gif-22845112",
	"https://tenor.com/view/eating-the-chip-chips-chip-eating-chip-man-eating-three-chips-gif-18885184",
	"https://tenor.com/view/coding-codingisfun-codingforkids-coding4kids-programming-gif-19847622",
	"https://tenor.com/view/touhou-fumo-touhou-gif-18786152",
	"https://tenor.com/view/soap-gay-bath-oops-gif-10322886",
	"https://media.discordapp.net/attachments/965777019189223474/966433793143611432/image0.gif",
	"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
}

local function getFunnyGif()
	return gifs[math.random(1, #gifs)]
end

local NetworkGuard = {} do
	
	local TaskAction = {
		Pass = "Pass",
		Hold = "Hold",
		Drop = "Drop",
		Kill = "Kill"
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
			
			self.DomainsWhitelist = {"githubusercontent.com", "pastebin.com", "fandom.com"}
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
	
	local function resolveTask(task, networkMethod, domain)
		
		local domainHandler = networkMethod:GetDomainHandler(domain)
		if domainHandler then
			return domainHandler(task)
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
	
	local function extractDomain(url)
		return url:match("[%w%.]*%.(%w+%.%w+)") or url:match("%w+%.%w+")
	end
	
	function NetworkGuard.new()
		local self = setmetatable({}, NetworkGuard)
		
		self.History = {}
		self.Methods = {}
		self.MaxLogHistory = 1
		
		local function httpHandler(networkMethod, instance, url, ...)
			local name = networkMethod.Name
			local domain = extractDomain(url)
			
			local task = self:NewTask(name, url, domain, networkMethod, instance, url, ...)
			
			return resolveTask(task, networkMethod, domain)
		end
		
		local function requestHandler(networkMethod, options, ...)
			local name = networkMethod.Name
			local url = rawget(options, "Url")
			local domain = extractDomain(url)
			
			local task = self:NewTask(name, url, domain, networkMethod, options, ...)
			
			return resolveTask(task, networkMethod, domain)
		end
		
		self:ProtectAsInstanceMethod("HttpGet", game, httpHandler)
		self:ProtectAsInstanceMethod("HttpGetAsync", game, httpHandler)
		self:ProtectAsInstanceMethod("HttpPost", game, httpHandler)
		self:ProtectAsInstanceMethod("HttpPostAsync", game, httpHandler)
		
		self:ProtectAsFunction(syn.websocket.connect, "websocket", httpHandler)
		
		local requestMethod = self:ProtectAsFunction(syn.request, "request", requestHandler)
		
		requestMethod:SetDomainHandler("httpbin.org", function(task)
			local body = [[
{
  "args": {}, 
  "headers": {
    "Accept": "*/*", 
    "Cookie": "%s", 
    "Host": "httpbin.org", 
    "Syn-Fingerprint": "%s", 
    "Syn-User-Identifier": "%s", 
    "User-Agent": "prohack3000", 
    "X-Amzn-Trace-Id": "%s"
  }, 
  "origin": "%s", 
  "url": "https://httpbin.org/get"
}]]
			
			local body = string.format(body, cookie(), getFunnyGif(), getFunnyGif(), getFunnyGif(), generateIp())
			
			warn(body)
			
			return {
				Body = body
			}
			
		end)
		
		return self
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
	
	function NetworkGuard:ProtectAsInstanceMethod(name, instance, handler)
		local networkMethod
		local rawClosure = instance[name]
		
		local newHttpMethod = function(instance, ...)
			local result = {handler(networkMethod, instance, ...)}
			return unpack(result)
		end
		
		local protected = newcclosure(newHttpMethod)
		
		kernel.HookHandler:HookGameIndex(name, instance, function(instance, name)
			return true, protected
		end)
		
		kernel.HookHandler:HookGameNamecall(name, instance, function(instance, name, ...)
			return true, newHttpMethod(...)
		end)
		
		networkMethod = NetworkMethod.new(rawClosure, handler, name)
		
		self.Methods[name] = networkMethod
		
		return networkMethod
	end
	
	
	function NetworkGuard:ProtectAsFunction(closure, name, handler)
		local networkMethod
		local rawClosure
		
		rawClosure = hookfunction(closure, function(...)
			local result = {handler(networkMethod, ...)}
			return unpack(result)
		end)
		
		networkMethod = NetworkMethod.new(rawClosure, handler, name)
		
		self.Methods[name] = networkMethod
		
		return networkMethod
	end
	
	buildFinalSingleton("NetworkGuard", NetworkGuard, DuskObject)
end

return NetworkGuard.new()