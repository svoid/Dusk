local initData = ...

local debugModeEnabled = initData.RawSettings.DebugModeEnabled

local print = print
local warn = warn

local pairs = pairs
local pcall = pcall
local tostring = tostring
local rawset = rawset
local rawget = rawget
local select = select

local srep = string.rep
local sgsub = string.gsub
local sformat = string.format
local tfind = table.find
local tclear = table.clear
local tinsert = table.insert
local unfcnormalize = utf8.nfcnormalize

local islclosure = islclosure
local getrawmetatable = getrawmetatable

-- reflection

local function iscclosure(func)
	return not islclosure(func)
end

local function getcallstacksize()
	local size = 2
	
	while debug.info(size, "f") do
		size += 1
	end
	
	return size - 2
end

local function isType(value, expectedType)
	return type(value) == expectedType
end

local function isClassTypeRaw(class, expectedType)
	return class.__type == expectedType
end

local function isClassType(class, expectedType)
	return isType(class, "table") and isClassTypeRaw(class, expectedType)
end

-- output

local function printf(...)
	print(sformat(...))
end

local function warnf(...)
	warn(sformat(...))
end

local function errorf(...)
	error(sformat(...), 2)
end


-- expanded output

local settings = {
	max_layer = 12,
	tab_string = "  ", -- console shortens \t to single space
	use_type_instead_tostring = true,
	ignore_tostring_metatable = true,
	add_instance_class_name = true,
	normalize_string = true,
	add_closure_type = true,
}

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

local function formatValue(v)
	local vtype = type(v)
	
	if vtype == "string" then
		v = sformat("\"%s\"", sgsub(v, "[\\\a\b\f\n\r\t\v\"\']", escape))
		
		if settings.normalize_string then
			local success, normalized = pcall(unfcnormalize, v)
			if success then
				return normalized
			end
		end
		
	elseif vtype == "table" then
		
		local metatable = getrawmetatable(v)
		if metatable then
			
			local __tostringValue = rawget(metatable, "__tostring")
			if __tostringValue then
				
				if settings.ignore_tostring_metatable then
					return tostring(v)
				end
				
				rawset(metatable, "__tostring", nil)
				local result = tostring(v)
				rawset(metatable, "__tostring", __tostringValue)
				
				return result
			end
			
			return tostring(v)
		end
		
		if settings.use_type_instead_tostring then
			return "<table>"
		end
		
	elseif vtype == "userdata" then
		vtype = typeof(v)
		if vtype == "Instance" then
			
			local className = ""
			if settings.add_instance_class_name then
				className = v.ClassName .. ": "
			end
			
			v = sformat("Instance: %s\"%s\"", className, sgsub(v:GetFullName(), "[\\\a\b\f\n\r\t\v\"\']", escape))
			
			if settings.normalize_string then
				local success, normalized = pcall(unfcnormalize, v)
				if success then
					return normalized
				end
			end
			
		else
			if settings.use_type_instead_tostring then
				return "<" .. vtype .. ">"
			end
			
			return sformat("%s(%s)", vtype, tostring(v))
		end
	elseif vtype == "vector" then
		return sformat("Vector3(%s)", tostring(v))
	elseif vtype == "function" then
		
		if settings.use_type_instead_tostring then
			if settings.add_closure_type then
				if islclosure(v) then
					return "<lclosure>"
				end
				return "<cclosure>"
			end
			return "<function>"
		end
		
	end
	
	return v
end

local printedTables = {}

local function expandedOutput(outputFunction, ...)
	local tab = settings.tab_string
	local maxLayer = settings.max_layer
	
	local layer = 0
	tclear(printedTables)
	
	local function printl(t)
		if layer == maxLayer then return end
		
		local tab = srep(tab, layer)
		
		if tfind(printedTables, t) then
			outputFunction(tab, "*** already printed ***")
			return
		end
		
		tinsert(printedTables, t)
		
		for i, v in pairs(t) do
			outputFunction(tab, i, formatValue(v))
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
			outputFunction(v)
		end
	end
end

local function layerOutput(outputFunction, t)
	for i, v in pairs(t) do
		outputFunction(i, formatValue(v))
	end
end

local function printe(...)
	expandedOutput(print, ...)
end

local function warne(...)
	expandedOutput(warn, ...)
end

local function printl(...)
	layerOutput(print, ...)
end

local function warnl(...)
	layerOutput(warn, ...)
end

-- assertation

local function assertf(expression, ...)
	if not expression then
		error(sformat(...), 2)
	end
	return expression
end

local function expectType(value, expectedType)
	if type(value) ~= expectedType then
		errorf("<%s> expected, got <%s>", expectedType, type(value))
	end
	return value
end

local function expectRBXType(value, expectedType)
	if typeof(value) ~= expectedType then
		errorf("<%s> expected, got <%s>", expectedType, typeof(value))
	end
	return value
end

local function expectClass(class)
	expectType(class, "table")
	assert(class.__type, "passed value is not a class")
	return class
end

local function expectClassTypeRaw(class, expectedType)
	if class.__type ~= expectedType then
		errorf("<%s> expected, got <%s>", expectedType, class.__type)
	end
	return class
end

local function expectClassType(class, expectedType)
	expectClass(class)
	expectClassTypeRaw(class, expectedType)
	return class
end


-- oop


local function buildClass(className, class, ...)
	local destructors = {class.Destroy}
	
	
	local baseClasses = {}
	
	rawset(class, "__base", baseClasses)
	
	for _, baseClass in ipairs({...}) do
		
		table.insert(baseClasses, baseClass)
		
		if className == baseClass.__type then
			errorf("'%s' cannot inherit itself", className)
		end
		
		for memberName, member in pairs(baseClass) do
			if memberName == "new" or string.sub(memberName, 1, 2) == "__" then continue end
			
			if memberName == "Destroy" then
				table.insert(destructors, member)
				continue
			end
			
			if class[memberName] then
				errorf("field '%s' of base class '%s' already exists in '%s'",
					memberName,
					baseClass.__type,
					className
				)
			end
			
			class[memberName] = member
		end
	end
	
	if #destructors > 0 then
		-- reverse destructors table for correct call order
		-- derived -> base
		local n = #destructors
		
		for i = 1, n do
			destructors[i], destructors[n] = destructors[n], destructors[i]
			n -= 1
		end
		
		function class:Destroy()
			for _, destructor in ipairs(destructors) do
				destructor(self)
			end
		end
	end
	
	return class
end

local instanceIndex = 0
local function finalizeClass(className, class)
	local index = rawget(class, "__index")
	if index == nil or type(index) == "table" and index ~= class then
		rawset(class, "__index", class)
	end
	
	rawset(class, "__type", className)
	
	if debugModeEnabled then
		local index = rawget(class, "__tostring")
		if index == nil then
			rawset(class, "__tostring", function(self)
				return tostring(self.__id) .. "_" .. self.__type
			end)
		end
		
		for key, value in pairs(class) do
			if type(value) == "function" and string.sub(key, 1, 2) ~= "__" then
				local wraped = function(...)
					local arguments = ""
					
					local isMethod = false
					
					local first = ...
					if type(first) == "table" and first.__type == className then
						isMethod = true
					end
					
					local size = select("#", ...)
					for i = isMethod and 2 or 1, size do
						local separator = ""
						
						if i < size then
							separator ..= ", "
						end
						
						arguments ..= tostring(select(i, ...)) .. separator
					end
					
					warnf("%s%s%s%s(%s)",
						string.rep("  ", getcallstacksize()),
						isMethod and tostring(first) or className,
						isMethod and ":" or ".",
						key,
						arguments
					)
					
					return value(...)
				end
				
				if key == "new" then
					class[key] = function(...)
						local instance = wraped(...)
						instance.__id = instanceIndex
						instanceIndex += 1
						return instance
					end
				else
					class[key] = wraped
				end
			end
		end
	end
	
	table.freeze(class)
end

local function convertToSingleton(class)
	local constructor = class.new
	
	local instance
	local function newConstructor(...)
		if instance then
			return instance
		end
		
		instance = constructor(...)
		return instance
	end
	
	class.new = newConstructor
end



local function buildFinalClass(className, class, ...)
	buildClass(className, class, ...)
	finalizeClass(className, class)
	return class
end

local function buildFinalSingleton(className, class, ...)
	buildClass(className, class, ...)
	convertToSingleton(class)
	finalizeClass(className, class)
	return class
end


local function buildFinalClassOverride(className, class, override, ...)
	buildClass(className, class, ...)
	
	for index, value in pairs(override) do
		class[index] = value
	end
	
	finalizeClass(className, class)
	return class
end

local function buildFinalSingletonOverride(className, class, override, ...)
	buildClass(className, class, ...)
	
	for index, value in pairs(override) do
		class[index] = value
	end
	
	convertToSingleton(class)
	finalizeClass(className, class)
	return class
end


-- misc


local function protectLib(library)
	
	if debugModeEnabled then
		return library
	end
	
	for index, value in pairs(library) do
		if type(value) == "function" and islclosure(value) then
			library[index] = newcclosure(value)
		end
	end
	
	return library
end

local library = {}

library.printf = printf
library.warnf = warnf
library.errorf = errorf

library.printe = printe
library.printl = printl
library.warne = warne
library.warnl = warnl

library.assertf = assertf
library.expectType = expectType
library.expectRBXType = expectRBXType
library.expectClass = expectClass
library.expectClassTypeRaw = expectClassTypeRaw
library.expectClassType = expectClassType

library.iscclosure = iscclosure
library.getcallstacksize = getcallstacksize
library.isDuskFunction = is_synapse_function
library.isType = isType
library.isClassTypeRaw = isClassTypeRaw
library.isClassType = isClassTypeRaw

library.buildClass = buildClass
library.convertToSingleton = convertToSingleton
library.finalizeClass = finalizeClass

library.buildFinalClass = buildFinalClass
library.buildFinalClassOverride = buildFinalClassOverride

library.buildFinalSingleton = buildFinalSingleton
library.buildFinalSingletonOverride = buildFinalSingletonOverride

library.protectLib = protectLib

return protectLib(library)