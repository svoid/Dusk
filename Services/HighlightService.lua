local createdPackages = {}

local Package = {} do
	
	Package.__index = Package

	Package.__newindex = function(self, k, v)
		asserttype(k, "string")
		
		local currentValue = self._Properties[k]
		if currentValue == nil then
			errorf("%s is not a valid member of package \"%s\"", k, self.Name)
		end
		
		asserttype(v, typeof(currentValue))
		
		self._Properties[k] = v
		
		for _, box in ipairs(self.Container:GetChildren()) do
			box[k] = v
		end
	end

	function Package.new(name)
		local self = {}
		self.Name = name
		self.Container = Instance.new("ScreenGui", game:GetService("CoreGui"))
		self.Container.Name = "Frame"
		self.Enabled = true
		self._Connections = {}
		self._Properties = {
			ZIndex = 1,
			Transparency = 0,
			Color3 = Color3.new(1, 1, 1)
		}

		createdPackages[name] = self
		return setmetatable(self, Package)
	end

	function Package:NewBox(part, zindex)
		local box = Instance.new("BoxHandleAdornment", self.Container)
		box.Name = "Frame"
		box.AlwaysOnTop = true
		box.Visible = self.Enabled

		if part then
			box.Size = part.Size
			box.Adornee = part
		else
			box.Size = Vector3.new(1, 1, 1)
		end
		
		for i, v in pairs(self._Properties) do
			box[i] = v
		end
		
		if zindex then
			asserttype(zindex, "number")
			box.ZIndex = zindex
		end
		
		return box
	end

	function Package:Clear()
		self.Container:ClearAllChildren()
		for _, connection in ipairs(self._Connections) do
			connection:Disconnect()
		end
		table.clear(self._Connections)
	end
	
	function Package:Destroy()
		createdPackages[self.Name] = nil
		self:Clear()
		setmetatable(self, nil)
		for i in pairs(self) do
			self[i] = nil
		end
	end

	function Package:SetEnabled(bool)
		self.Enabled = bool
		for _, box in ipairs(self.Container:GetChildren()) do
			box.Visible = bool
		end
	end

	function Package:Enable()
		self:SetEnabled(true)
	end

	function Package:Disable()
		self:SetEnabled(false)
	end

	function Package:RegisterConnection(connection)
		table.insert(self._Connections, connection)
	end
end

--[[
		External
--]]

function methods:GetAllPackages()
	local list = {}
	for i, v in pairs(createdPackages) do
		list[i] = v
	end
	return list
end

function methods:CreatePackage(name)
	asserttype(name, "string")
	assert(createdPackages[name] == nil, "package already exist")
	
	return Package.new(name)
end

function methods:GetPackage(name)
	return createdPackages[name]
end

function methods:GetClearPackage(name)
	local package = createdPackages[name]
	if package then
		package:Destroy()
	end
	return Package.new(name)
end
