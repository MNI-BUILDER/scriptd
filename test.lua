local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UI_NAMES = { "Gear_Shop", "Seed_Shop", "SeasonPassUI", "PetShop_UI" }
local UI_PADDING = 20
local SCROLL_SPEED = 0.12
local UI_SCALE = 0.75
local SCROLL_PAUSE_TIME = 1.2
local RESCAN_INTERVAL = 1
local DEBUG = false
local SEASON_UI_SIZE_MULTIPLIER = 1.18

local function dbg(...)
	if DEBUG then print("[AutoScroll DEBUG]", ...) end
end

local function safe(fn, ctx)
	local ok, err = pcall(fn)
	if not ok then
		warn(("AutoScroll ERROR (%s): %s"):format(ctx or "unknown", tostring(err)))
		if DEBUG then print(debug.traceback()) end
	end
	return ok, err
end

local foundUIs = {}

local function tryAddUI(ui)
	safe(function()
		for _, name in ipairs(UI_NAMES) do
			if ui and ui.Name == name and not table.find(foundUIs, ui) then
				table.insert(foundUIs, ui)
				ui.Enabled = true
				if ui:IsA("ScreenGui") then
					ui.ResetOnSpawn = false
					ui.IgnoreGuiInset = false
				end
				dbg("Added UI:", ui.Name)
			end
		end
	end, "tryAddUI")
end

safe(function()
	for _, name in ipairs(UI_NAMES) do
		local ui = playerGui:FindFirstChild(name)
		if ui then tryAddUI(ui) end
	end
end, "initial UI find")

playerGui.ChildAdded:Connect(function(child)
	safe(function() tryAddUI(child) end, "ChildAdded tryAddUI")
end)

local corners = {
	{anchor = Vector2.new(0,0), pos = UDim2.new(0, UI_PADDING, 0, UI_PADDING)},
	{anchor = Vector2.new(1,0), pos = UDim2.new(1, -UI_PADDING, 0, UI_PADDING)},
	{anchor = Vector2.new(0,1), pos = UDim2.new(0, UI_PADDING, 1, -UI_PADDING)},
	{anchor = Vector2.new(1,1), pos = UDim2.new(1, -UI_PADDING, 1, -UI_PADDING)},
}

local function arrangeUIs()
	safe(function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local view = cam.ViewportSize
		local baseW, baseH = math.floor(view.X * 0.35), math.floor(view.Y * 0.45)

		for idx, ui in ipairs(foundUIs) do
			local corner = corners[((idx-1) % #corners) + 1]
			local mult = (ui.Name == "SeasonPassUI") and SEASON_UI_SIZE_MULTIPLIER or 1
			local uiW, uiH = math.floor(baseW * mult), math.floor(baseH * mult)

			for _, child in ipairs(ui:GetChildren()) do
				if child:IsA("Frame") or child:IsA("ImageLabel") or child:IsA("ScrollingFrame") then
					safe(function()
						child.Visible = true
						child.AnchorPoint = corner.anchor
						child.Position = corner.pos
						child.Size = UDim2.new(0, uiW, 0, uiH)
						local sc = child:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
						sc.Parent = child
						sc.Scale = UI_SCALE
					end, "arrange "..child:GetFullName())
				end
			end
		end
	end, "arrangeUIs")
end

arrangeUIs()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		safe(arrangeUIs, "ViewportSize arrangeUIs")
	end)
end

local managed = {}

local function findLayout(sf)
	return sf:FindFirstChildOfClass("UIListLayout")
		or sf:FindFirstChildOfClass("UIGridLayout")
		or sf:FindFirstChildOfClass("UIPageLayout")
end

local function findManaged(frame)
	for _, e in ipairs(managed) do
		if e.frame == frame then return e end
	end
end

local function hookLayout(sf, entry, layoutObj, contentFrame)
	entry.layout = layoutObj
	entry.contentFrame = contentFrame
	local function updateCanvas()
		safe(function()
			if not entry.frame or not entry.frame.Parent then return end
			local acs = layoutObj.AbsoluteContentSize
			if acs and (acs.Y > 0 or acs.X > 0) then
				if layoutObj:IsA("UIGridLayout") then
					entry.frame.CanvasSize = UDim2.new(0, acs.X, 0, acs.Y)
				else
					entry.frame.CanvasSize = UDim2.new(0, 0, 0, acs.Y)
				end
				dbg("Canvas from layout", entry.frame:GetFullName(), acs)
			end
		end, "updateCanvas "..tostring(entry.frame and entry.frame:GetFullName()))
	end
	layoutObj:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
	task.defer(updateCanvas)
end

local function addManaged(sf)
	safe(function()
		if findManaged(sf) then return end
		local layout = findLayout(sf)
		local entry = { frame = sf, layout = layout, contentFrame = nil, currentY = (sf.CanvasPosition and sf.CanvasPosition.Y) or 0 }
		table.insert(managed, entry)
		sf.ScrollingEnabled = true
		sf.ScrollBarThickness = 8
		dbg("Managed:", sf:GetFullName())

		if layout then hookLayout(sf, entry, layout, nil) end

		local content = sf:FindFirstChild("Content")
		if content and content:IsA("Frame") then
			local innerLayout = content:FindFirstChildOfClass("UIListLayout")
				or content:FindFirstChildOfClass("UIGridLayout")
				or content:FindFirstChildOfClass("UIPageLayout")
			if innerLayout then
				hookLayout(sf, entry, innerLayout, content)
				dbg("Hooked Content", sf:GetFullName(), content:GetFullName())
			else
				content.DescendantAdded:Connect(function(d)
					if not entry.layout and (d:IsA("UIListLayout") or d:IsA("UIGridLayout") or d:IsA("UIPageLayout")) then
						hookLayout(sf, entry, d, content)
						dbg("Late layout Content", sf:GetFullName(), d:GetFullName())
					end
				end)
			end
			coroutine.wrap(function()
				while entry.frame and entry.frame.Parent do
					local ok, acs = pcall(function() return sf.AbsoluteCanvasSize end)
					if ok and acs and acs.Y and acs.Y > 0 and not entry.layout then
						sf.CanvasSize = UDim2.new(0, 0, 0, acs.Y)
						dbg("Canvas from AbsoluteCanvasSize", sf:GetFullName(), acs.Y)
					end
					task.wait(1)
				end
			end)()
		end

		sf.DescendantAdded:Connect(function(d)
			if not entry.layout and (d:IsA("UIListLayout") or d:IsA("UIGridLayout") or d:IsA("UIPageLayout")) then
				hookLayout(sf, entry, d, (d.Parent and d.Parent ~= sf) and d.Parent or nil)
				dbg("Late layout", sf:GetFullName(), d:GetFullName())
			end
		end)
	end, "addManaged")
end

local function computeContentHeight(entry)
	local f = entry.frame
	if not f then return 0 end
	if f.AbsoluteCanvasSize and f.AbsoluteCanvasSize.Y and f.AbsoluteCanvasSize.Y > 0 then
		return f.AbsoluteCanvasSize.Y
	end
	if entry.layout and entry.layout.AbsoluteContentSize and entry.layout.AbsoluteContentSize.Y and entry.layout.AbsoluteContentSize.Y > 0 then
		return entry.layout.AbsoluteContentSize.Y
	end
	local total = 0
	local parent = entry.contentFrame or f
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UILayout") and child.AbsoluteSize and child.AbsoluteSize.Y then
			total += math.max(0, child.AbsoluteSize.Y)
		end
	end
	return total
end

local function getMaxScroll(entry)
	local f = entry.frame
	if not f or not f.Parent then return 0 end
	if f.AbsoluteCanvasSize and f.AbsoluteWindowSize and f.AbsoluteCanvasSize.Y and f.AbsoluteWindowSize.Y and f.AbsoluteWindowSize.Y > 0 then
		return math.max(0, f.AbsoluteCanvasSize.Y - f.AbsoluteWindowSize.Y)
	end
	local content = computeContentHeight(entry)
	if f.AbsoluteSize and f.AbsoluteSize.Y and f.AbsoluteSize.Y > 0 then
		return math.max(0, content - f.AbsoluteSize.Y)
	end
	return 0
end

local function rescanAll()
	safe(function()
		for _, ui in ipairs(foundUIs) do
			for _, desc in ipairs(ui:GetDescendants()) do
				if desc:IsA("ScrollingFrame") then
					addManaged(desc)
				end
			end
			if ui.Name == "SeasonPassUI" then
				for _, d in ipairs(ui:GetDescendants()) do
					if d.Name == "Store" then
						if d:IsA("ScrollingFrame") then
							addManaged(d)
							dbg("Store direct SF", d:GetFullName())
						else
							for _, inner in ipairs(d:GetDescendants()) do
								if inner:IsA("ScrollingFrame") then
									addManaged(inner)
									dbg("Store inner SF", inner:GetFullName())
									local content = inner:FindFirstChild("Content")
									if content and content:IsA("Frame") then
										local il = content:FindFirstChildOfClass("UIListLayout")
											or content:FindFirstChildOfClass("UIGridLayout")
										if il then
											local e = findManaged(inner)
											if e then
												hookLayout(inner, e, il, content)
												dbg("Store force Content", inner:GetFullName(), content:GetFullName())
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end, "rescanAll")
end

rescanAll()
task.spawn(function()
	while true do
		rescanAll()
		task.wait(RESCAN_INTERVAL)
	end
end)

local direction, progress, paused, pauseTimer = 1, 0, false, 0

local function progressToY(p, entry)
	local max = getMaxScroll(entry)
	if max <= 0 then return 0 end
	return math.clamp(p, 0, 1) * max
end

RunService.RenderStepped:Connect(function(dt)
	if #managed == 0 then return end

	if paused then
		pauseTimer += dt
		if pauseTimer >= SCROLL_PAUSE_TIME then
			paused = false
			pauseTimer = 0
			direction = -direction
			dbg("Resume dir", direction)
		else
			return
		end
	end

	progress += dt * direction * SCROLL_SPEED
	if progress >= 1 then
		progress = 1
		paused = true
	elseif progress <= 0 then
		progress = 0
		paused = true
	end

	for _, entry in ipairs(managed) do
		local f = entry.frame
		if not f or not f.Parent then continue end
		if f.AbsoluteSize and f.AbsoluteSize.Y > 0 then
			local maxScroll = getMaxScroll(entry)
			if maxScroll > 0 then
				local target = progressToY(progress, entry)
				entry.currentY = entry.currentY or (f.CanvasPosition and f.CanvasPosition.Y) or 0
				local alpha = math.clamp(10 * dt, 0, 1)
				entry.currentY += (target - entry.currentY) * alpha
				local y = math.floor(entry.currentY + 0.5)
				local ok, err = pcall(function()
					f.CanvasPosition = Vector2.new(0, y)
				end)
				if not ok then dbg("CanvasPosition fail", f:GetFullName(), err) end
			end
		else
			dbg("Wait AbsoluteSize", f:GetFullName())
		end
	end
end)

dbg("Auto-scroll loaded. DEBUG = true for verbose.")
