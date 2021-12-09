local Permission = NewEnum("Permission", {
	NotAccessibleSecurity = -1,
	None = 0,
	Script = 2,
	LocalUserSecurity = 4,
	RobloxScriptSecurity = 5,
	RobloxSecurity = 5,
	PluginSecurity = 6
}, true)

local InstanceProtoTags = NewEnum("InstanceProtoTag", {
	"AddToReturnPool"
})

local Dump = game:GetService("HttpService"):JSONDecode(storage.ApiDump:Read()).Classes

local classes = {}

for _, classData in ipairs(Dump) do
	local className = classData.Name
	if className == "Studio" then continue end
	local members = {}
	local classBody = {
		Members = members,
		Superclass = classData.Superclass,
	}
	
	for _, memberData in ipairs(classData.Members) do
		if memberData.MemberType ~= "Property" then continue end
		
		local tags = memberData.Tags
		if tags and (table.find(tags, "ReadOnly") or table.find(tags, "NotScriptable") or table.find(tags, "Deprecated")) then
			continue
		end
		
		members[memberData.Name] = memberData.Security.Write or 0
	end
	classes[className] = classBody
end


local function IterateProperties(className)
	local class = assert(classes[className], "invalid class name")
	local members = class.Members
	
	return function(_, memberName)
		local permission
		
		memberName, permission = next(members, memberName)
		
		while not memberName do
			className = class.Superclass
			if className == "<<<ROOT>>>" then return end
			class = classes[className]
			members = class.Members
			
			memberName = nil
			memberName, permission = next(members, memberName)
		end
		
		return memberName, permission
	end
end

local SaveNames = false

local layer = 0
local str = ""

local sformat = string.format

local function update(...)
	str ..= sformat(...)
end

local function updatel(ptt, ...)
	update("\n" .. ("\t"):rep(layer) .. ptt, ...)
end

local DecimalPivot = 10 ^ 4
local function fnumber(num)
	return tostring(math.floor(num * DecimalPivot + 0.5) / DecimalPivot)
end


--[[
		Serialization
--]]


local function serializeItem(v)
	local vtype = typeof(v)
	
	if vtype == "number" then
		v = fnumber(v)
	elseif vtype == "nil" or vtype == "boolean" or vtype == "EnumItem" then
		return tostring(v)
	elseif vtype == "string" then
		v = sformat("\"%s\"", fescape(v))
	elseif vtype == "Color3" then
		v = sformat("Color3.fromRGB(%d, %d, %d)", v.R * 255, v.G * 255, v.B * 255)
	elseif vtype == "Vector2" then
		v = sformat("Vector2.new(%s, %s)", fnumber(v.X), fnumber(v.Y))
	elseif vtype == "Vector3" then
		v = sformat("Vector3.new(%s, %s, %s)", fnumber(v.X), fnumber(v.Y), fnumber(v.Z))
	elseif vtype == "CFrame" then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:components()
		v = sformat("CFrame.new(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
			fnumber(x), fnumber(y), fnumber(x),
			fnumber(r00), fnumber(r01), fnumber(r02),
			fnumber(r10), fnumber(r11), fnumber(r12),
			fnumber(r20), fnumber(r21), fnumber(r22)
		)
	elseif vtype == "BrickColor" then
		v = sformat("BrickColor.new(%d)", v.Number)
	elseif vtype == "UDim2" then
		v = sformat("UDim2.new(%s, %d, %s, %d)", fnumber(v.X.Scale), v.X.Offset, fnumber(v.Y.Scale), v.Y.Offset)
	elseif vtype == "UDim" then
		v = sformat("UDim.new(%s, %f)", fnumber(v.Scale), v.Offset)
	elseif vtype == "Rect" then
		v = sformat("Rect.new(%f, %f, %f, %f)", v.Min.X, v.Min.Y, v.Max.X, v.Max.Y)
	elseif vtype == "NumberRange" then
		v = sformat("NumberRange.new(%f,%f)", v.Min, v.Max)
	elseif vtype == "ColorSequence" then
		local out = "ColorSequence.new("
		for _, point in ipairs(v.Keypoints) do
			out ..= sformat("ColorSequenceKeypoint.new(%f, Color3.fromRGB(%d, %d, %d)),", point.Time, point.Value.r * 255, point.Value.g * 255, point.Value.b * 255)
		end
		v = out .. ")"
	elseif vtype == "NumberSequence" then
		local out = "NumberSequence.new("
		for _, point in ipairs(v.Keypoints) do
			out ..= sformat("NumberSequenceKeypoint.new(%f, %f, %f),", point.Time, point.Value, point.Envelope)
		end
		v = out .. ")"
	else
		v = false
	end
	
	return v
	
end

local function serializeMember(obj, identity, attributes, isTagged)
	updatel("{")
	layer += 1
	updatel("{ClassName = \"%s\"},", obj.ClassName)
	layer -= 1
	
	updatel("{")
	layer += 1
	for name, permission in IterateProperties(obj.ClassName) do
		if name == "Name" and not SaveNames then continue end
		if name == "Parent" then continue end
		if name == "Archivable" then continue end
		if canaccesspermission(identity, Permission[permission]) then
			local part = serializeItem(obj[name])
			if part then
				updatel("%s = %s,", name, part)
			end
		end
	end
	layer -= 1
	updatel("},")
	
	
	updatel("{")
	layer += 1
	for _, child in ipairs(obj:GetChildren()) do
		if child.Archivable then
			serializeMember(child, identity, attributes, isTagged)
			update(",")
		end
	end
	layer -= 1
	updatel("},")
	
	
	if attributes then
		updatel("{")
		layer += 1
		if isTagged then
			for name, value in pairs(obj:GetAttributes())do
				updatel("[Tags.%s] = %s,", name, serializeItem(value))
			end
		else
			for name, value in pairs(obj:GetAttributes())do
				updatel("%s = %s,", name, serializeItem(value))
			end
		end
		layer -= 1
		updatel("},")
	end
	
	updatel("}")
end

local function serialize(obj, identity, attributes, isTagged)
	layer = 0
	str = ""
	serializeMember(obj, identity, attributes, isTagged)
	return str
end


--[[
		Deserialization
--]]


local function deserialize(structure, parent)
	local readonly = structure[1]
	local obj = Instance.new(readonly.ClassName)
	
	for i, v in pairs(structure[2]) do
		obj[i] = v
	end
	
	for _, child in ipairs(structure[3]) do
		deserialize(child, obj)
	end
	
	local attributes = structure[4]
	if attributes then
		for i, v in pairs(attributes) do
			obj:SetAttribute(i, v)
		end
	end
	
	obj.Parent = parent
	return obj
end

local deserializeTagged do
	local pool
	
	local Tags = InstanceProtoTags
	local TagHandlers = {
		[Tags.AddToReturnPool] = function(obj, name)
			pool[name] = obj
		end,
	}
	
	local function taggedConstructor(structure, parent)
		local readonly = structure[1]
		local obj = Instance.new(readonly.ClassName)
		for i, v in pairs(structure[2]) do
			obj[i] = v
		end
		
		for _, child in ipairs(structure[3]) do
			taggedConstructor(child, obj)
		end
		
		for i, v in pairs(structure[4]) do
			TagHandlers[i](obj, v)
		end
		
		obj.Parent = parent
		return obj
	end
	
	function deserializeTagged(structure, parent)
		pool = {}
		return taggedConstructor(structure, parent), pool
	end
	
end


--[[
		External
--]]


function methods:Serialize(...)
	return serialize(...)
end

function methods:Deserialize(...)
	return deserialize(...)
end

function methods:DeserializeTagged(...)
	return deserializeTagged(...)
end
