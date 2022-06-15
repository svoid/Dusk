
local Cache = {} do
	
	function Cache.new(constructor)
		local self = setmetatable({}, Cache)
		
		self._Constructor = constructor
		self._ExpansionSize = 10
		
		self._Stored = {}
		self._GetNextPosition = self:_Expand()
		
		self._InUse = {}
		self._InUseNextPosition = 0
		
		return self
	end
	
	function Cache:Destroy()
		for _, item in ipairs(self._Stored) do
			item:Destroy()
		end
		
		for _, item in ipairs(self._InUse) do
			item:Destroy()
		end
		
		self._Stored = nil
		self._InUse = nil
		self._Constructor = nil
	end
	
	function Cache:Get()
		local getPosition = self._GetNextPosition
		if getPosition == 0 then
			getPosition = self:_Expand()
		end
		
		local stored = self._Stored
		local item = stored[getPosition]
		stored[getPosition] = nil
		getPosition -= 1
		
		self._GetNextPosition = getPosition
		
		self._InUseNextPosition += 1
		self._InUse[self._InUseNextPosition] = item
		
		return item
	end
	
	function Cache:Store(item)
		local inUse = self._InUse
		local index = table.find(inUse, item)
		if not index then
			error("item does not belong to this cache")
		end
		
		table.remove(inUse, index)
		
		self._InUseNextPosition -= 1
		
		self._GetNextPosition += 1
		self._Stored[self._GetNextPosition] = item
	end
	
	function Cache:IterateStored(i)
		local stored = self._Stored
		return stored, next(stored, i)
	end
	
	function Cache:IterateInUse(i)
		local inUse = self._InUse
		return inUse, next(inUse, i)
	end
	
	function Cache:ForEachStored(callback)
		for i, part in ipairs(self._Stored) do
			callback(i, part)
		end
	end
	
	function Cache:ForEachInUse(callback)
		for i, part in ipairs(self._InUse) do
			callback(i, part)
		end
	end
	
	function Cache:ForEach(callback)
		self:ForEachStored(callback)
		self:ForEachInUse(callback)
	end
	
	function Cache:_Expand()
		local expansionSize = self._ExpansionSize
		
		local stored = self._Stored
		local constructor = self._Constructor
		for i = 1, expansionSize do
			stored[i] = constructor()
		end
		
		return expansionSize
	end
	
	buildFinalClass("Cache", Cache, DuskObject)
end


local CCache = {} do
	
	function CCache.new(constructor, cleaner)
		local self = setmetatable(Cache.new(constructor), CCache)
		
		self._Cleaner = cleaner
		
		return self
	end
	
	local override = {}
	
	function override:Store(item)
		Cache.Store(self, item)
		self._Cleaner(item)
	end
	
	buildFinalClassOverride("CCache", CCache, override, Cache)
end

local library = {}

library.Cache = Cache
library.CCache = CCache

return protectLib(library)