local kernel = ...
local DuskObject = kernel:GetMainBaseClass()

local debugModeEnabled = kernel.Settings:GetField("DebugModeEnabled")
local environment = kernel.Environment

local hotkeysHandler

local inputLibrary = kernel:GetLibrary("input")

local KeyCodeSequence = inputLibrary.KeyCodeSequence
local Binding = inputLibrary.Binding
local toBinding = inputLibrary.toBinding
local HotkeyGroup = inputLibrary.HotkeyGroup
local HotkeysHandler = inputLibrary.HotkeysHandler



local Event = {} do
	
	function Event.new(name)
		local self = setmetatable({}, Event)
		
		self.Name = name
		self._Listeners = {}
		
		return self
	end
	
	function Event:_Dispatch(...)
		for _, listener in ipairs(self._Listeners) do
			listener(...)
		end
	end
	
	function Event:_AddListener(listener)
		table.insert(self._Listeners, listener)
	end
	
	function Event:_RemoveListener(listener)
		local index = table.find(self._Listeners, listener)
		
		if not index then
			errorf("function in not a listener of ")
		end
		assert(index, "function is not listener of")
	end
	
	buildFinalClass("Event", Event)
end

local EventEmitter = {} do
	
	function EventEmitter.new()
		local self = setmetatable({}, EventEmitter)
		
		self._Events = {}
		
		return self
	end
	
	function EventEmitter:Destroy()
		for _, event in ipairs(self._Events) do
			event:Destroy()
		end
	end
	
	function EventEmitter:AddListener(name, listener)
		expectType(name, "string")
		expectType(listener, "function")
		
		local events = self._Events
		local event = events[name]
		
		if not event then
			event = Event.new(name)
			events[name] = event
		end
		
		event:_AddListener(listener)
	end
	
	function EventEmitter:Emit(name, ...)
		local event = self._Events[name]
		
		if event then
			event:_Dispatch(...)
		end
	end
	
	function EventEmitter:RemoveListener(name, listener)
		local event = self._Events[name]
		
		if event then
			event:RemoveListener(listener)
		end
	end
	
	function EventEmitter:Once(name, listener)
		local function callback(...)
			listener(...)
			self:RemoveListener(name, callback)
		end
		self:AddListener(name, callback)
	end
	
	function EventEmitter:On(name, listener)
		self:AddListener(name, listener)
	end
	
	finalizeClass("EventEmitter", EventEmitter)
end

local DuskInstance = {} do
	
	function DuskInstance:Destroy()
		EventEmitter.Destroy(self)
	end
	
	buildFinalClass("DuskInstance", DuskInstance, EventEmitter, DuskObject)
end




--[[
		UI
--]]




local CoreGui = {} do
	
	local Colors = {
		Debug = Color3.fromRGB(255, 85, 0),
		Background = Color3.fromRGB(45, 45, 48),
		
		GroupLabelHover = Color3.fromRGB(62, 62, 64),
		GroupLabelSubHover = Color3.fromRGB(85, 85, 85),
		
		Category = Color3.fromRGB(27, 27, 28),
		CategorySelected = Color3.fromRGB(51, 51, 52),
		
		ActiveText = Color3.fromRGB(230, 230, 230),
		InactiveText = Color3.fromRGB(100, 100, 100),
		
		WorkspaceLabelActive = Color3.fromRGB(0, 122, 204),
		WorkspaceLabelSelection = Color3.fromRGB(28, 151, 234),
		
		WorkspaceLabelSubActive = Color3.fromRGB(28, 151, 234),
		WorkspaceLabelSubSelection = Color3.fromRGB(82, 176, 239),
	}
	
	local CORE_FONT = Enum.Font.Arial
	local CORE_FONT_SIZE = 14
	local LABEL_TEXT_OFFSET = 20
	local LABEL_WIDTH = 300
	local LABEL_HEIGHT = 20
	local GUI_INSET_OFFSET = 36
	local GROUP_HOLDER_SIZE = 30
	local WORKSPACE_LABELS_HOLDER_SIZE = 20
	
	local GROUP_LABEL_WIDTH_ALIGNMENT = 20
	local VECTOR2_HUGE = Vector2.new(math.huge, math.huge)
	
	local function isIn(x, y, guiObject)
		--y -= GUI_INSET_OFFSET WTF
		
		local min = guiObject.AbsolutePosition
		if x < min.X or y < min.Y then
			return false
		end
		
		local max = min + guiObject.AbsoluteSize
		if x > max.X or y > max.Y then
			return false
		end
		
		return true
	end
	
	local getLabelSize do
		local TextService = game:GetService("TextService")
		
		function getLabelSize(name, alignment)
			alignment = alignment or 0
			local textSize = TextService:GetTextSize(name, CORE_FONT_SIZE, CORE_FONT, VECTOR2_HUGE).X
			return UDim2.new(0, textSize + GROUP_LABEL_WIDTH_ALIGNMENT, 0, LABEL_HEIGHT)
		end
	end
	
	local CORE_DISPLAY_ORDER = -1
	local WORKSPACE_DISPLAY_ORDER_OFFSET = 1
	local CONTEXT_MENU_DISPLAY_ORDER_OFFSET = 2
	
	local screenGuiCache do
		local coreGui = game:GetService("CoreGui")
		
		local function constructor()
			local screenGui = Instance.new("ScreenGui")
			
			syn.protect_gui(screenGui)
			
			screenGui.DisplayOrder = CORE_DISPLAY_ORDER
			screenGui.OnTopOfCoreBlur = true
			screenGui.Parent = coreGui
			
			return screenGui
		end
		
		local function cleaner(screenGui)
			screenGui:ClearAllChildren()
			screenGui.DisplayOrder = CORE_DISPLAY_ORDER
		end
		
		local CCache = kernel:GetLibrary("cache").CCache
		screenGuiCache = CCache.new(constructor, cleaner)
	end
	
	local ContextMenuScreen = {} do
		
		function ContextMenuScreen.new()
			local self = setmetatable({}, ContextMenuScreen)
			
			local screen = screenGuiCache:Get()
			screen.DisplayOrder = CORE_DISPLAY_ORDER + CONTEXT_MENU_DISPLAY_ORDER_OFFSET
			screen.Name = "ContextMenuScreen"
			
			self._Holder = screen
			self._Content = nil
			self._Size = nil
			self._Position = nil
			
			return self
		end
		
		function ContextMenuScreen:Destroy()
			self._Holder = nil
			self._Content = nil
			self._Position = nil
			self._Size = nil
		end
		
		function ContextMenuScreen:IsIn(x, y)
			local content = self._Content
			if not content then
				return false
			end
			
			return isIn(x, y, content)
		end
		
		
		function ContextMenuScreen:IsOccupied()
			return not not self._Content
		end
		
		function ContextMenuScreen:Set(root, relative)
			self._Content = root
			self._Size = root.Size
			self._Position = root.Position
			
			local relativeSize = relative.AbsoluteSize
			local size = root.Size
			
			root.Size = UDim2.fromOffset(
				relativeSize.X * size.X.Scale + size.X.Offset,
				relativeSize.Y * size.Y.Scale + size.Y.Offset
			)
			
			local relativePosition = relative.AbsolutePosition
			local position = root.Position
			
			root.Position = UDim2.fromOffset(
				relativePosition.X + relativeSize.X * position.X.Scale + position.X.Offset,
				relativePosition.Y + relativeSize.Y * position.Y.Scale + position.Y.Offset
			)
			
			root.Parent = self._Holder
		end
		
		function ContextMenuScreen:Free()
			local content = self._Content
			if content then
				content.Parent = nil
				content.Size = self._Size
				content.Position = self._Position
			end
			self._Content = nil
		end
		
		buildFinalClass("ContextMenuScreen", ContextMenuScreen, DuskObject)
	end
	
	local contextMenuScreen = ContextMenuScreen.new()
	
	-- workspace system
	
	local WorkspaceLabel = {} do
		
		local CLOSE_BUTTON_BORDER_OFFSET = 4
		local CLOSE_BUTTON_SIZE = LABEL_HEIGHT - CLOSE_BUTTON_BORDER_OFFSET
		local CLOSE_BUTTON_OFFSET = UDim2.new(0, CLOSE_BUTTON_SIZE / 2, 0, 0)
		
		function WorkspaceLabel.new(handler, workspace, name)
			local self = setmetatable({}, WorkspaceLabel)
			
			self._Handler = handler
			self._Workspace = workspace
			
			local label = Instance.new("TextLabel", handler._LabelsHolder)
			label.Name = "WorkspaceLabel"
			label.BorderSizePixel = 0
			label.BackgroundTransparency = 1
			label.BackgroundColor3 = Colors.WorkspaceLabelSelection
			label.Font = CORE_FONT
			label.TextSize = CORE_FONT_SIZE
			label.TextColor3 = Colors.ActiveText
			label.TextXAlignment = Enum.TextXAlignment.Left
			
			self.Root = label
			
			self._LabelInputBegan = label.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					self._Workspace:Select()
				end
			end)
			
			local close = Instance.new("TextLabel", label)
			close.Name = "close"
			close.TextSize = CLOSE_BUTTON_SIZE - CLOSE_BUTTON_BORDER_OFFSET
			close.Text = "X"
			close.Font = Enum.Font.Arial
			close.TextColor3 = Colors.ActiveText
			close.BorderSizePixel = 0
			close.BackgroundTransparency = 1
			close.BackgroundColor3 = Colors.GroupLabelHover
			close.Size = UDim2.new(0, CLOSE_BUTTON_SIZE, 0, CLOSE_BUTTON_SIZE)
			close.Position = UDim2.new(1, -CLOSE_BUTTON_BORDER_OFFSET, .5, 0)
			close.AnchorPoint = Vector2.new(1, .5)
			
			self._CloseButton = close
			
			close.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					self._Workspace:Destroy()
				end
			end)
			
			close.MouseEnter:Connect(function()
				if contextMenuScreen:IsOccupied() then return end
				close.BackgroundTransparency = 0
			end)
			
			close.MouseLeave:Connect(function()
				if contextMenuScreen:IsOccupied() then return end
				close.BackgroundTransparency = 1
			end)
			
			self:_SetNameNoUpdate(name or "unnamed")
			self:Update()
			
			return self
		end
		
		function WorkspaceLabel:Destroy()
			self:DisableMouseEvents()
			
			self.Root:Destroy()
			self.Root = nil
			self._Workspace = nil
			
			self._Handler:_RemoveLabel(self)
			self._Handler = nil
			
			self._LabelInputBegan:Disconnect()
			self._LabelInputBegan = nil
		end
		
		function WorkspaceLabel:EnableMouseEvents()
			local label = self.Root
			
			self._LabelMouseEnter = label.MouseEnter:Connect(function()
				if contextMenuScreen:IsOccupied() then return end
				label.BackgroundTransparency = 0
			end)
			
			self._LabelMouseLeave = label.MouseLeave:Connect(function()
				if contextMenuScreen:IsOccupied() then return end
				label.BackgroundTransparency = 1
			end)
		end
		
		function WorkspaceLabel:DisableMouseEvents()
			if self._LabelMouseEnter then
				self._LabelMouseEnter:Disconnect()
				self._LabelMouseEnter = nil
				
				self._LabelMouseLeave:Disconnect()
				self._LabelMouseLeave = nil
			end
		end
		
		function WorkspaceLabel:Update()
			local workspace = self._Workspace
			
			if workspace.IsSelected then
				self:DisableMouseEvents()
				self.Root.BackgroundTransparency = 0
				
				if workspace.Group.IsSelected then
					self.Root.BackgroundColor3 = Colors.WorkspaceLabelActive
					self._CloseButton.BackgroundColor3 = Colors.WorkspaceLabelSubActive
				else
					self.Root.BackgroundColor3 = Colors.GroupLabelHover
					self._CloseButton.BackgroundColor3 = Colors.GroupLabelSubHover
				end
			else
				self:EnableMouseEvents()
				self.Root.BackgroundTransparency = 1
				self.Root.BackgroundColor3 = Colors.WorkspaceLabelSelection
				self._CloseButton.BackgroundColor3 = Colors.WorkspaceLabelSubSelection
			end
		end
		
		function WorkspaceLabel:_SetNameNoUpdate(name)
			self.Root.Size = getLabelSize(name) + CLOSE_BUTTON_OFFSET
			self.Root.Text = " " .. name
		end
		
		function WorkspaceLabel:SetName(name)
			self:_SetNameNoUpdate(name)
			self._Handler:_Update()
		end
		
		buildFinalClass("WorkspaceLabel", WorkspaceLabel, DuskObject)
	end
	
	local WorkspaceLabelsHandler = {} do
		
		local GROUP_LABEL_WIDTH_ALIGNMENT = 20
		
		function WorkspaceLabelsHandler.new(group)
			local self = setmetatable({}, WorkspaceLabelsHandler)
			
			self.Labels = {}
			self.Group = group
			
			local labelsHolder = Instance.new("Frame", group.Screen._WorkspaceRoot)
			labelsHolder.Name = "labelsHolder"
			labelsHolder.Size = UDim2.new(1, 0, 0, WORKSPACE_LABELS_HOLDER_SIZE)
			labelsHolder.BackgroundTransparency = 1
			
			self._LabelsHolder = labelsHolder
			
			return self
		end
		
		function WorkspaceLabelsHandler:NewLabel(workspace, name)
			local label = WorkspaceLabel.new(self, workspace, name)
			table.insert(self.Labels, label)
			self:_Update()
			return label
		end
		
		function WorkspaceLabelsHandler:_RemoveLabel(label)
			local labels = self.Labels
			table.remove(labels, table.find(labels, label))
			self:_Update()
		end
		
		function WorkspaceLabelsHandler:_Update()
			local offset = 0
			for _, workspaceLabel in ipairs(self.Labels) do
				local label = workspaceLabel.Root
				label.Position = UDim2.new(0, offset, 0, 0)
				offset += label.AbsoluteSize.X
			end
		end
		
		buildFinalClass("WorkspaceLabelsHandler", WorkspaceLabelsHandler, DuskObject)
	end
	
	local Workspace = {} do
		
		function Workspace.new(group)
			local self = setmetatable({}, Workspace)
			
			self.Group = group
			self._Label = nil
			self.IsSelected = false
			
			local root = Instance.new("Frame")
			root.Size = UDim2.fromScale(1, 1)
			root.BackgroundColor3 = Colors.Debug
			root.BorderSizePixel = 0
			
			self.Root = root
			
			return self
		end
		
		function Workspace:Destroy()
			self._Label:Destroy()
			self._Label = nil
			
			self.Group:_RemoveWorkspace(self)
			self.Group = nil
			
			self.Root:Destroy()
			self.Root = nil
		end
		
		function Workspace:Select()
			self.IsSelected = true
			self.Group:_Select(self)
			self._Label:Update()
		end
		
		function Workspace:_Deselect()
			self.IsSelected = false
			self._Label:Update()
		end
		
		buildFinalClass("Workspace", Workspace, DuskObject)
	end
	
	local WorkspaceGroup = {} do
		
		function WorkspaceGroup.new(screen)
			local self = setmetatable({}, WorkspaceGroup)
			
			self.Workspaces = {}
			self.Screen = screen
			self.ActiveWorkspace = nil
			self.IsSelected = false
			
			self._WorkspaceLabelsHandler = WorkspaceLabelsHandler.new(self)
			
			local workspaceContentRoot = Instance.new("Frame", screen._WorkspaceRoot)
			workspaceContentRoot.Name = "workspaceContentRoot"
			workspaceContentRoot.Size = UDim2.new(1, 0, 1, -WORKSPACE_LABELS_HOLDER_SIZE)
			workspaceContentRoot.Position = UDim2.new(0, 0, 0, WORKSPACE_LABELS_HOLDER_SIZE)
			workspaceContentRoot.BorderSizePixel = 0
			
			self._WorkspaceContentRoot = workspaceContentRoot
			
			workspaceContentRoot.InputBegan:Connect(function(input)
				if not self.IsSelected and
					(input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.MouseButton2
					or input.UserInputType == Enum.UserInputType.MouseButton3) then
					self:_Select(self.ActiveWorkspace)
				end
			end)
			
			return self
		end
		
		function WorkspaceGroup:Destroy()
			self.ActiveWorkspace = nil
			
			local workspaces = self.Workspaces
			for i, workspace in ipairs(workspaces) do
				workspace:Destroy()
				workspaces[i] = nil
			end
			
			self.Screen:_RemoveGroup(self)
			self.Screen = nil
		end
		
		function WorkspaceGroup:NewWorkspace(name)
			local workspace = Workspace.new(self)
			table.insert(self.Workspaces, workspace)
			
			local label = self._WorkspaceLabelsHandler:NewLabel(workspace, name)
			workspace._Label = label
			
			return workspace
		end
		
		function WorkspaceGroup:_RemoveWorkspace(workspace)
			local workspaces = self.Workspaces
			local pos = table.find(workspaces, workspace)
			local nextWorkspace = workspaces[pos + 1] or workspaces[pos - 1]
			
			table.remove(workspaces, pos)
			
			if nextWorkspace then
				if workspace == self.ActiveWorkspace then
					self.ActiveWorkspace = nil
				end
				nextWorkspace:Select()
			else
				self:Destroy()
			end
		end
		
		function WorkspaceGroup:_Select(workspace)
			self.IsSelected = true
			workspace.Root.Parent = self._WorkspaceContentRoot
			
			local activeWorkspace = self.ActiveWorkspace
			if activeWorkspace and activeWorkspace ~= workspace then
				activeWorkspace:_Deselect()
				activeWorkspace.Root.Parent = nil
			end
			
			self.ActiveWorkspace = workspace
			self.Screen:_Select(self)
		end
		
		function WorkspaceGroup:_Deselect()
			self.IsSelected = false
			self.ActiveWorkspace:_Deselect()
		end
		
		function WorkspaceGroup:Update()
			local offset = 0
			for _, workspace in ipairs(self.Workspaces) do
				workspace._Label.Position = UDim2.new(offset, 0, 0, 0)
				offset += 123
			end
		end
		
		buildFinalClass("WorkspaceGroup", WorkspaceGroup, DuskObject)
	end
	
	local WorkspaceScreen = {} do
		
		function WorkspaceScreen.new(handler)
			local self = setmetatable({}, WorkspaceScreen)
			
			local root = screenGuiCache:Get()
			root.DisplayOrder = CORE_DISPLAY_ORDER + WORKSPACE_DISPLAY_ORDER_OFFSET
			
			self.Groups = {}
			self.Handler = handler
			self.Root = root
			self.ActiveGroup = nil
			self.IsSelected = false
			
			self.IsFloating = false
			self._TopbarInputBegan = nil
			self._TopbarInputChanged = nil
			self._UserInputServiceInputChanged = nil
			
			local workspaceRoot = Instance.new("Frame", root)
			workspaceRoot.Name = "workspaceRoot"
			workspaceRoot.Size = UDim2.new(0, 400, 0, 400)
			workspaceRoot.BackgroundColor3 = Colors.Background
			workspaceRoot.BorderSizePixel = 0
			
			self._WorkspaceRoot = workspaceRoot
			
			local topbar = Instance.new("Frame", workspaceRoot)
			topbar.Name = "topbar"
			topbar.AnchorPoint = Vector2.new(0, 1)
			topbar.BackgroundColor3 = Colors.Background
			topbar.Size = UDim2.new(1, 0, 0, 30)
			topbar.Visible = false
			
			self._Topbar = topbar
			
			local close = Instance.new("TextLabel", topbar)
			close.Name = "close"
			close.TextSize = 14
			close.Text = "X"
			close.Font = Enum.Font.Arial
			close.BackgroundTransparency = 1
			close.BackgroundColor3 = Colors.GroupLabelHover
			close.Size = UDim2.new(0, 30, 0, 30)
			close.Position = UDim2.new(1, 0, 0, 0)
			close.AnchorPoint = Vector2.new(1, 0)
			
			self._CloseButton = close
			
			close.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					self:Destroy()
				end
			end)
			
			close.MouseEnter:Connect(function()
				close.BackgroundTransparency = 0
			end)
			
			close.MouseLeave:Connect(function()
				close.BackgroundTransparency = 1
			end)
			
			local defaultGroup = self:_NewGroup()
			self.ActiveGroup = defaultGroup
			
			return self
		end
		
		function WorkspaceScreen:Destroy()
			self:DisableFloating()
			
			local groups = self.Groups
			for i, group in ipairs(groups) do
				group:Destroy()
				groups[i] = nil
			end
			
			screenGuiCache:Store(self.Root)
			self.Root = nil
			
			self.Handler:_RemoveScreen(self)
			self.Handler = nil
		end
		
		function WorkspaceScreen:NewWorkspace(name)
			return self.ActiveGroup:NewWorkspace(name)
		end
		
		function WorkspaceScreen:_NewGroup()
			local group = WorkspaceGroup.new(self)
			table.insert(self.Groups, group)
			return group
		end
		
		function WorkspaceScreen:_RemoveGroup(group)
			local groups = self.Groups
			table.remove(groups, table.find(groups, group))
		end
		
		function WorkspaceScreen:EnableFloating()
			self.IsFloating = true
			self._CloseButton.Visible = true
			
			local isDragging = false
			local root = self.workspaceRoot
			
			local dragStart
			local startPos
			
			self._Topbar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					isDragging = true
					dragStart = input.Position
					startPos = root.Position
					
					local conn
					conn = input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then
							isDragging = false
							conn:Disconnect()
						end
					end)
				end
			end)
			
			local dragInput
			
			self._Topbar.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					dragInput = input
				end
			end)
			
			game:GetService("UserInputService").InputChanged:Connect(function(input)
				if isDragging and input == dragInput then
					local delta = input.Position - dragStart
					root.Position = UDim2.new(
						startPos.X.Scale,
						startPos.X.Offset + delta.X,
						startPos.Y.Scale,
						startPos.Y.Offset + delta.Y
					)
				end
			end)
		end
		
		function WorkspaceScreen:DisableFloating()
			self.IsFloating = false
			self._CloseButton.Visible = false
			
			local connection = self._TopbarInputBegan
			if connection then
				connection:Disconnect()
				self._TopbarInputBegan = nil
			end
			
			local connection = self._TopbarInputChanged
			if connection then
				connection:Disconnect()
				self._TopbarInputChanged = nil
			end
			
			local connection = self._UserInputServiceInputChanged
			if connection then
				connection:Disconnect()
				self._UserInputServiceInputChanged = nil
			end
		end
		
		function WorkspaceScreen:_Select(group)
			self.IsSelected = true
			self.ActiveGroup = group
			self.Handler:_SelectScreen(self)
		end
		
		function WorkspaceScreen:_Deselect()
			self.IsSelected = false
			self.ActiveGroup:_Deselect()
		end
		
		buildFinalClass("WorkspaceScreen", WorkspaceScreen, DuskObject)
	end
	
	local WorkspaceScreenHandler = {} do
		
		function WorkspaceScreenHandler.new(coreGUI)
			local self = setmetatable({}, WorkspaceScreenHandler)
			
			self.CoreGui = coreGUI
			self.Screens = {}
			self.MainScreen = nil
			self.ActiveScreen = nil
			
			return self
		end
		
		function WorkspaceScreenHandler:Destroy()
			local screens = self.Screens
			for i, screen in ipairs(screens) do
				screen:Destroy()
				screens[i] = nil
			end
			
			self.MainScreen = nil
		end
		
		function WorkspaceScreenHandler:NewScreen(activate)
			local screen = WorkspaceScreen.new(self, activate)
			
			local screens = self.Screens
			if #screens == 0 then
				self.MainScreen = screen
				
				local root = screen._WorkspaceRoot
				root.Position = UDim2.new(0, 0, 0, GROUP_HOLDER_SIZE)
				root.Size = UDim2.new(0, 400, 0, 400)
				--root.Size = UDim2.new(1, 0, 1, -GROUP_HOLDER_SIZE)
			end
			
			table.insert(screens, screen)
			
			return screen
		end
		
		function WorkspaceScreenHandler:NewWorkspace(name, activate)
			local screen = self.ActiveScreen
			
			if not self.ActiveScreen then
				activate = true
				screen = self:NewScreen(true)
			end
			
			local workspace = screen:NewWorkspace(name)
			
			if activate then
				workspace:Select()
			end
			
			return workspace
		end
		
		function WorkspaceScreenHandler:_SelectScreen(screen)
			self.ActiveScreen = screen
			self.CoreGui:_SetActiveScreen(screen)
		end
		
		function WorkspaceScreenHandler:_DeselectScreen(screen)
			self.ActiveScreen:_Deselect()
			self.ActiveScreen = screen
			self.CoreGui:_SetActiveScreen(screen)
		end
		
		function WorkspaceScreenHandler:_RemoveScreen(screen)
			local screens = self.Screens
			table.remove(screens, table.find(screens, screen))
		end
		
		buildFinalClass("WorkspaceScreenHandler", WorkspaceScreenHandler, DuskObject)
	end
	
	-- topbar content
	
	local Label = {} do
		
		local LABEL_TEXT_SIZE = (LABEL_WIDTH - LABEL_TEXT_OFFSET) / 2
		
		function Label.new(handler, binding)
			local self = setmetatable({}, Label)
			
			local label = Instance.new("Frame", handler.Root)
			label.BorderSizePixel = 0
			label.BackgroundColor3 = Colors.CategorySelected
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(0, LABEL_WIDTH, 0, LABEL_HEIGHT - 1)
			
			local textFrame = Instance.new("TextLabel", label)
			textFrame.BackgroundTransparency = 1
			textFrame.Text = binding.Name
			textFrame.TextSize = CORE_FONT_SIZE
			textFrame.Font = CORE_FONT
			textFrame.TextColor3 = Colors.ActiveText
			textFrame.TextXAlignment = Enum.TextXAlignment.Left
			textFrame.Position = UDim2.new(0, LABEL_TEXT_OFFSET, 0, 0)
			textFrame.Size = UDim2.new(0, LABEL_TEXT_SIZE, 1, 0)
			
			local bindFrame = Instance.new("TextLabel", label)
			bindFrame.BackgroundTransparency = 1
			bindFrame.Text = tostring(binding.KeyCodeSequence)
			bindFrame.TextSize = CORE_FONT_SIZE
			bindFrame.Font = CORE_FONT
			bindFrame.TextColor3 = Colors.ActiveText
			bindFrame.TextXAlignment = Enum.TextXAlignment.Left
			bindFrame.Position = UDim2.new(0, LABEL_TEXT_OFFSET + LABEL_TEXT_SIZE, 0, 0)
			bindFrame.Size = UDim2.new(0, LABEL_TEXT_SIZE, 1, 0)
			
			self.Root = label
			self.TextFrame = textFrame
			self.BindFrame = bindFrame
			self.Enabled = true
			
			self.Handler = handler
			
			label.InputBegan:Connect(function(input)
				if self.Enabled and input.UserInputType == Enum.UserInputType.MouseButton1 then
					binding:Call()
				end
			end)
			
			label.MouseEnter:Connect(function()
				if self.Enabled then
					handler:Highlight(self)
				end
			end)
			
			label.MouseLeave:Connect(function()
				if self.Enabled then
					handler:Unhighlight(self)
				end
			end)
			
			return self
		end
		
		function Label:Highlight()
			self.Root.BackgroundTransparency = 0
		end
		
		function Label:Unhighlight()
			self.Root.BackgroundTransparency = 1
		end
		
		function Label:Enable()
			self.Enabled = true
			self.TextFrame.TextColor3 = Colors.InactiveText
			self.BindFrame.TextColor3 = Colors.InactiveText
		end
		
		function Label:Disable()
			self.Enabled = false
			self.TextFrame.TextColor3 = Colors.ActiveText
			self.BindFrame.TextColor3 = Colors.ActiveText
			self:Unhighlight()
		end
		
		function Label:Destroy()
			self.Root:Destroy()
			self.TextFrame:Destroy()
			self.BindFrame:Destroy()
		end
		
		buildFinalClass("Label", Label, DuskObject)
	end

	local Category = {} do
		
		function Category.new(handler)
			local self = setmetatable({}, Category)
			
			self.Handler = handler
			
			self.Labels = {}
			self._HighlightedLabel = nil
			
			self.YSize = 0
			
			local root = Instance.new("Frame", handler._CategoriesHolder)
			root.BackgroundTransparency = 1
			
			self.Root = root
			
			local delimiter = Instance.new("Frame", root)
			delimiter.Visible = false
			delimiter.Size = UDim2.new(1, 0, 0, 1)
			delimiter.Position = UDim2.new(0, 0, 1, -2)
			delimiter.BorderSizePixel = 0
			delimiter.BackgroundColor3 = Colors.CategorySelected
				
			self.DelimiterEnabled = false
			self.Delimiter = delimiter
			
			return self
		end
		
		function Category:Destroy()
			for _, label in ipairs(self.Labels) do
				label:Destroy()
			end
			self.Root:Destroy()
			self.Handler = nil
		end
		
		function Category:NewLabel(...)
			local binding = toBinding(...)
			local label = Label.new(self, binding)
			table.insert(self.Labels, label)
			
			self:Update()
			self.Handler:Update()
			return label
		end
		
		function Category:DestroyLabel(label)
			local labels = self.Labels
			table.remove(labels, table.find(labels, label))
			
			self:Update()
			self.Handler:Update()
		end
		
		function Category:Highlight(label)
			local highlightedLabel = self._HighlightedLabel
			if highlightedLabel then
				highlightedLabel:Unhighlight(highlightedLabel)
			end
			self._HighlightedLabel = highlightedLabel
			label:Highlight()
		end
		
		function Category:Unhighlight(label)
			label:Unhighlight()
		end
		
		function Category:Update()
			self.YSize = #self.Labels * LABEL_HEIGHT + (self.DelimiterEnabled and 3 or 0) - 1
			self.Root.Size = UDim2.new(0, LABEL_WIDTH, 0, self.YSize)
			
			local yoffset = 0
			for _, label in ipairs(self.Labels) do
				label.Root.Position = UDim2.new(0, 0, 0, yoffset)
				yoffset += LABEL_HEIGHT
			end
		end
		
		function Category:EnableDelimiter()
			self.DelimiterEnabled = true
			self.Delimiter.Visible = true
			self.YSize += 3
			self:Update()
		end
		
		function Category:DisableDelimiter()
			self.DelimiterEnabled = false
			self.Delimiter.Visible = false
			self.YSize -= 3
			self:Update()
		end
		
		buildFinalClass("Category", Category, DuskObject)
	end

	local Group = {} do
		
		function Group.new(name, handler)
			local self = setmetatable({}, Group)
			
			self.Name = name
			
			local label = Instance.new("TextLabel", handler.Holder)
			label.Text = name
			label.TextSize = CORE_FONT_SIZE
			label.Font = CORE_FONT
			label.TextColor3 = Colors.ActiveText
			label.BackgroundColor3 = Colors.Category
			label.BackgroundTransparency = 1
			label.BorderSizePixel = 0
			label.AnchorPoint = Vector2.new(0, .5)
			
			label.Size = getLabelSize(name, GROUP_LABEL_WIDTH_ALIGNMENT)
			
			self.Root = label
			self._Handler = handler
			
			local categoriesHolder = Instance.new("Frame")
			categoriesHolder.Visible = false
			categoriesHolder.Position = UDim2.new(0, 1, 1, 0)
			categoriesHolder.BackgroundColor3 = Colors.Category
			categoriesHolder.BorderColor3 = Colors.Category
			
			self._CategoriesHolder = categoriesHolder
			self.Categories = {}
			self._LastCategory = nil
			
			label.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					handler:Open(self)
					handler:Activate()
				end
			end)
			
			return self
		end
		
		function Group:Destroy()
			self.Root:Destroy()
			self._CategoriesHolder:Destroy()
			for _, category in ipairs(self.Categories) do
				category:Destroy()
			end
			self._Handler:_RemoveGroup(self)
			
			self:Deactivate()
		end
		
		function Group:Activate()
			local handler = self._Handler
			
			self._LabelMouseEnter = self.Root.MouseEnter:Connect(function()
				handler:Open(self)
			end)
		end
		
		function Group:Deactivate()
			if self._LabelMouseEnter then
				self._LabelMouseEnter:Disconnect()
				self._LabelMouseEnter = nil
				
				self:DisableMouseLeaveEvents()
			end
		end
		
		function Group:EnableMouseLeaveEvents()
			local label = self.Root
			local handler = self._Handler
			local categoriesHolder = self._CategoriesHolder
			
			self._CategoriesHolderMouseLeave = categoriesHolder.MouseLeave:Connect(function(x, y)
				if not isIn(x, y, label) then
					handler:Close(self)
				end
			end)
			
			self._LabelMouseLeave = label.MouseLeave:Connect(function(x, y)
				if not isIn(x, y, categoriesHolder) then
					handler:Close(self)
				end
			end)
		end
		
		function Group:DisableMouseLeaveEvents()
			if not self._CategoriesHolderMouseLeave then return end
			
			self._CategoriesHolderMouseLeave:Disconnect()
			self._CategoriesHolderMouseLeave = nil
			
			self._LabelMouseLeave:Disconnect()
			self._LabelMouseLeave = nil
		end
		
		function Group:NewCategory()
			if self._LastCategory then
				self._LastCategory:EnableDelimiter()
			end
			
			local newCategory = Category.new(self)
			table.insert(self.Categories, newCategory)
			self._LastCategory = newCategory
			
			self:Update()
			return newCategory
		end
		
		function Group:_RemoveCategory(category)
			local categories = self.Categories
			local index = table.find(categories, category)
			
			if index == #categories then
				categories[index - 1]:DisableDelimiter()
			end
			
			table.remove(categories, index)
		end
		
		function Group:Open()
			self.Root.BackgroundTransparency = 0
			contextMenuScreen:Set(self._CategoriesHolder, self.Root)
			self._CategoriesHolder.Visible = true
		end
		
		function Group:Close()
			self.Root.BackgroundTransparency = 1
			contextMenuScreen:Free()
			self._CategoriesHolder.Visible = false
			self:DisableMouseLeaveEvents()
		end
		
		function Group:Update()
			local requiredYSize = 0
			for _, category in ipairs(self.Categories) do
				category.Root.Position = UDim2.new(0, 0, 0, requiredYSize)
				requiredYSize += category.YSize
			end
			self._CategoriesHolder.Size = UDim2.new(0, LABEL_WIDTH, 0, requiredYSize)
		end
		
		buildFinalClass("Group", Group, DuskObject)
	end

	local GroupHandler = {} do
		
		function GroupHandler.new(rootFrame)
			local self = setmetatable({}, GroupHandler)
			
			local groupHolder = Instance.new("Frame", rootFrame)
			groupHolder.Size = UDim2.new(1, 0, 0, GROUP_HOLDER_SIZE)
			groupHolder.BackgroundColor3 = Colors.Background
			groupHolder.BorderSizePixel = 0
			
			self.Root = rootFrame
			self.Groups = {}
			self.Holder = groupHolder
			self.LastOpenedGroup = nil
			
			self.Active = false
			self.IsInConnection = nil
			
			return self
		end
		
		function GroupHandler:Destroy()
			self:Deactivate()
			
			for _, group in ipairs(self.Groups) do
				group:Destroy()
			end
		end
		
		local UserInputService = game:GetService("UserInputService")
		function GroupHandler:Activate()
			if self.Active then return end
			
			self.Active = true
			for _, group in ipairs(self.Groups) do
				group:Activate()
			end
			
			task.wait()
			
			self.IsInConnection = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					local position = input.Position
					self:CheckDeactivation(position.X, position.Y)
				end
			end)
		end
		
		function GroupHandler:CheckDeactivation(x, y)
			for _, group in ipairs(self.Groups) do
				if isIn(x, y, group.Root) then return end
			end
			
			if contextMenuScreen:IsIn(x, y) then return end
			
			self:Deactivate()
		end
		
		function GroupHandler:Deactivate()
			if not self.Active then return end
			
			self.Active = false
			for _, group in ipairs(self.Groups) do
				group:Deactivate()
			end
			
			self:CloseLastOpenedGroup()
			
			if self.IsInConnection then
				self.IsInConnection:Disconnect()
				self.IsInConnection = nil
			end
		end
		
		function GroupHandler:CloseLastOpenedGroup()
			local lastOpenedGroup = self.LastOpenedGroup
			if lastOpenedGroup then
				self:Close(lastOpenedGroup)
			end
		end
		
		function GroupHandler:Open(group)
			self:CloseLastOpenedGroup()
			self.LastOpenedGroup = group
			group:Open()
		end
		
		function GroupHandler:Close(group)
			self.LastOpenedGroup = nil
			group:Close()
		end
		
		function GroupHandler:NewGroup(name)
			local group = Group.new(name, self)
			table.insert(self.Groups, group)
			self:Update()
			return group
		end
		
		function GroupHandler:GetGroup(name)
			for _, group in ipairs(self.Groups) do
				if group.Name == name then
					return group
				end
			end
		end
		
		function GroupHandler:_RemoveGroup(group)
			table.remove(self.Groups, table.find(self.Groups, group))
			self:Update()
		end
		
		function GroupHandler:Update()
			local offset = 0
			for _, group in ipairs(self.Groups) do
				local label = group.Root
				label.Position = UDim2.new(0, offset, .5, 0)
				offset += label.AbsoluteSize.X
			end
		end
		
		buildFinalClass("GroupHandler", GroupHandler, DuskObject)
	end
	
	function CoreGui.new()
		local self = setmetatable({}, CoreGui)
		
		local root = screenGuiCache:Get()
		
		local topbar = Instance.new("Frame", root)
		topbar.BackgroundColor3 = debugModeEnabled and Colors.Debug or Colors.Background
		topbar.BorderSizePixel = 0
		topbar.AnchorPoint = Vector2.new(0, 1)
		topbar.Size = UDim2.new(1, 0, 0, GUI_INSET_OFFSET)
		
		local background = Instance.new("Frame", root)
		background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		background.Size = UDim2.new(1, 0, 1, 0)
		background.BorderSizePixel = 0
		background.BackgroundTransparency = 0.5
		
		self._GroupHandler = GroupHandler.new(background)
		self._WorkspaceScreenHandler = WorkspaceScreenHandler.new(self)
		
		self.ActiveScreen = nil
		self.ActiveWorkspaceGroup = nil
		self.ActiveWorkspace = nil
		
		self.ContextMenuScreen = contextMenuScreen
		self.ScreenGuiCache = screenGuiCache
		
		return self
	end
	
	function CoreGui:Destroy()
		self._GroupHandler:Destroy()
		screenGuiCache:Destroy()
		contextMenuScreen:Destroy()
	end
	
	function CoreGui:NewGroup(name)
		return self._GroupHandler:NewGroup(name)
	end
	
	function CoreGui:GetGroup(name)
		return self._GroupHandler:GetGroup(name)
	end
	
	function CoreGui:NewScreen()
		return self._WorkspaceScreenHandler:NewScreen()
	end
	
	function CoreGui:NewWorkspace(name, activate)
		return self._WorkspaceScreenHandler:NewWorkspace(name, activate)
	end
	
	function CoreGui:_SetActiveScreen(screen)
		local activeGroup = screen.ActiveGroup
		
		self.ActiveScreen = screen
		self.ActiveWorkspaceGroup = activeGroup
		self.ActiveWorkspace = activeGroup.ActiveWorkspace
	end
	
	buildFinalSingleton("CoreGui", CoreGui, DuskObject)
end



--[[
		Core
--]]



local function setupBinding()
	hotkeysHandler = HotkeysHandler.new()
	
	local workspaceGroup = hotkeysHandler:NewGroup()
	
	
	local function closeActiveWorkspace()
		warn("closeActiveWorkspace")
	end
	
	workspaceGroup:NewBinding(closeActiveWorkspace, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)
	workspaceGroup:Enable()
	
	return hotkeysHandler
end

local function initSecurityGroup(coreGui)
	local group = coreGui:NewGroup("security")
	
	local category = group:NewCategory()
	category:NewLabel("help", printidentity)
	category:NewLabel("help2", printidentity)
	
	local category = group:NewCategory()
	category:NewLabel("help", printidentity)
	category:NewLabel("help2", printidentity)
end

local Core = {} do
	
	function Core.new()
		local self = setmetatable({}, Core)
		
		kernel:GetEnvironment().core = self
		self.Gui = CoreGui.new()
		initSecurityGroup(self.Gui)
		setupBinding()
		
		return self
	end
	
	function Core:Destroy()
		self.Gui:Destroy()
		hotkeysHandler:Destroy()
	end
	
	buildFinalSingleton("Core", Core, DuskObject)
end



--[[
		Entry point
--]]



local function main()
	
	local oldCore = core or (dusk and dusk.core)
	
	if oldCore then
		oldCore:Destroy()
	end
	
	local core = Core.new()
	local coreGui = core.Gui
	
	local group = coreGui:NewGroup("hello wdafdddddfddd")
	
	local category = group:NewCategory()
	category:NewLabel("help", printidentity)
	category:NewLabel("help2", printidentity)
	
	local category = group:NewCategory()
	category:NewLabel("help", printidentity)
	category:NewLabel("help2", printidentity, Enum.KeyCode.A, Enum.KeyCode.A, Enum.KeyCode.A, Enum.KeyCode.A)
	
	print("\n\n\n\n\n\n")
	
	local workspacy = coreGui:NewWorkspace("sad")
	local label = Instance.new("TextLabel", workspacy.Root)
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Text = "im sad label"
	label.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
	label.Name = "Contentasdaw"
	
	local workspacy2 = coreGui:NewWorkspace("2sad")
	local label = Instance.new("TextLabel", workspacy2.Root)
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Text = "im too sad label"
	label.BackgroundColor3 = Color3.fromRGB(170, 255, 0)
	label.Name = "Contentasdaw"
end

main()