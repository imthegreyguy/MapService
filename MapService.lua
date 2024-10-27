--[[
	This file serves as a service for handling map generation,
	as well as serving access of the map to other scripts that need it.
]]

----------| Module Definiton |----------
local MapService = {}

----------| Globals |----------

----------| Roblox Services |----------
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

----------| References |----------
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = Shared:WaitForChild("Classes")
local Prefabs = ServerStorage:WaitForChild("Prefabs")
local Remotes = Shared:WaitForChild("Remotes")

local SendMapGridEvent = Remotes:WaitForChild("SendMapGrid")

local HexTemplate = Prefabs:WaitForChild("HexagonGrid")

----------| Modules |----------
local HexGrid = require(Classes:WaitForChild("HexGrid"))
local BiomeTypes = require(Classes.HexGrid.BiomeTypes)

----------| Types |----------

----------| Constants |----------
local _OFFSETS = {
	{1, 0}, {1, 1}, --Down, down and right
	{0, -1}, {0, 1}, --Left and right
	{-1, 0}, {-1, 1}, --Up, up and right
	{0,0} --Current Grid
}

----------| Private Variables |----------
local _inStudio = RunService:IsStudio()

local _delayRow = true
local _delayColumn = false
local _visualizeGeneration = not _inStudio
local _animateGeneration = not _inStudio

local _mapGrid = {}
local _generating = false

----------| Public Variables |----------

------------------||------------------
------------------||------------------
------------------||------------------

----------| Functions |----------
--Tweens a specific hexagon to a position.
local function _tweenHex(hexagon, position)
	if not _animateGeneration then return end
	if not hexagon then return end
	if not hexagon.Model then return end
	
	--Not sure if a CFrame can be directly tweened, so a CFrameValue is used as a workaround.
	local CFrameValue = Instance.new("CFrameValue")
	CFrameValue.Value = hexagon.Model:GetPivot()
	
	--As the CFrameValue is updated, also update the actual hexagon Model.
	CFrameValue:GetPropertyChangedSignal("Value"):Connect(function()
		if not hexagon then return end
		if not hexagon.Model then return end
		hexagon.Model:PivotTo(CFrameValue.Value)
	end)

	local tween = TweenService:Create(
		CFrameValue, 
		TweenInfo.new(0.5), 
		{Value = CFrame.new(position)}
	)
	tween:Play()

	tween.Completed:Connect(function()
		CFrameValue:Destroy()
	end)
end

--Loops through and parents every hexagon to the world.
local function _parentMapToWorld(canAnimate)
	if canAnimate == nil then canAnimate = true end
	
	for _, row in _mapGrid do
		if _delayRow then task.wait() end
		for _, hexagon in row do
			if _delayColumn then task.wait() end
			if hexagon then
				if _animateGeneration and canAnimate then
					_tweenHex(hexagon, hexagon.Position)
				else
					hexagon.Model:PivotTo(CFrame.new(hexagon.Position))
				end
				hexagon.Model.Parent = game.Workspace.Grids
			end
		end
	end
end

--Parents a specific hexagon to the world.
local function _parentHexagonToWorld(hexagon, canAnimate)
	if not hexagon then return end
	if not hexagon.Model then return end
	if not hexagon.Position then return end
	
	if canAnimate == nil then canAnimate = true end
	
	if _animateGeneration and canAnimate then
		_tweenHex(hexagon, hexagon.Position)
	else
		hexagon.Model:PivotTo(CFrame.new(hexagon.Position))
	end
	hexagon.Model.Parent = game.Workspace.Grids
end

--Adds the surrounding and selected hexagon's heights together and divides
--	to get the average height. Useful for smoothening the world.
local function _getSurroundingGridsAverageHeight(rowIndex, columnIndex)
	local totalHeight = 0
	local count = 0
	
	--Loops through the offsets table which stores the relative position
	--	of surrounding grids.
	for _, offset in _OFFSETS do
		local neighborRow = rowIndex + offset[1]
		local neighborCol = columnIndex + offset[2]

		if _mapGrid[neighborRow] then
			if _mapGrid[neighborRow][neighborCol] then
				local neighborHex = _mapGrid[neighborRow][neighborCol]
				totalHeight += neighborHex.Position.Y
			else
				totalHeight += -1
			end
		else
			totalHeight += -1
		end

		count += 1
	end

	if totalHeight == 0 or count == 0 then return 0 end
	return totalHeight / count
end

--Utilizes the distance formula to find if a grid is within the islands radius.
--Also adds some randomization so the island isnt a uniform shape.
local function _isWithinIsland(x, z, centerX, centerZ, radius)
	local dx = x - centerX
	local dz = z - centerZ
	local distance = math.sqrt((dx * dx) + (dz * dz))
	
	local randomNumber = math.random(2,10)
	local randomOffset = math.noise(x/randomNumber, z/randomNumber) * randomNumber
	return distance + randomOffset <= radius
end

--Loops through the entire grid X amount of times and smoothens it out
--	using the surrounding height average.
local function _smoothenGrid(smootheningPasses)
	for i = 1, smootheningPasses do
		for rowIndex, row in _mapGrid do
			if _delayRow then task.wait() end
			for columnIndex, hexagon in row do
				if _delayColumn then task.wait() end
				local averageSurroundingHeight = _getSurroundingGridsAverageHeight(rowIndex, columnIndex)

				local currentPos = hexagon.Position
				hexagon.Position = Vector3.new(currentPos.X, averageSurroundingHeight, currentPos.Z)
				
				if _visualizeGeneration then _parentHexagonToWorld(hexagon) end	
			end	
		end
	end
end

--Checks if the specific grid has a nil surrounding it.
local function _hasSurroundingNil(rowIndex, columnIndex)
	--Loops through the offsets which stores the relative position of grids around
	--	the specified grid.
	for _, offset in ipairs(_OFFSETS) do
		local neighborRow = rowIndex + offset[1]
		local neighborCol = columnIndex + offset[2]

		if not _mapGrid[neighborRow] or not _mapGrid[neighborRow][neighborCol] then
			--Returns true if it finds a single nil grid.
			return true
		end
	end
	--Returns false if no grids are nil.
	return false
end

--Checks if the entire grid is nil.
local function _entireGridNil()
	for _, row in _mapGrid do
		for _, hexagon in row do
			if hexagon then
				return false
			end
		end
	end
	return true
end

--Loops through the gridLength and gridWidth to populate the base 2D grid array.
local function _createHexagonGrid(gridLength, gridWidth, hexWidth, hexLength, centerX, centerZ, islandRadius, startX, startZ)
	for row = 0, gridLength - 1 do
		if _delayRow then task.wait() end
		_mapGrid[row] = {}
		for column = 0, gridWidth - 1 do
			if _delayColumn then task.wait() end
			local xPos = startX + column * hexWidth
			--Because hexagons are offset depending if the row is even or odd, we can
			--	apply that offset by checking if it is in an even row.
			if row % 2 ~= 0 then
				xPos = xPos + hexWidth / 2
			end
			local zPos = startZ + row * (hexLength * 0.75)
			
			--Check if the hexagon is within the island radius and create a new Hexagon
			--	instance at that position in the 2D array.
			if _isWithinIsland(row, column, centerX, centerZ, islandRadius) then
				_mapGrid[row][column] = HexGrid.New({
					position = Vector3.new(xPos, 0, zPos),
					rowIndex = row,
					columnIndex = column
				})
				
				if _visualizeGeneration then _parentHexagonToWorld(_mapGrid[row][column], false) end
			else
				--If that hex is not within the island radius, set that position to nil.
				_mapGrid[row][column] = nil
			end
		end
	end
end

--Apply the heights to the hexagons.
--I split this from the _createHexagonGrid function because
--	the animations would not rise from the water.
--Splitting this comes with the downside of taking a bit longer,
--	but that is okay!
local function _assignHexagonHeights(heightOffset)
	local randomLargeScaleMultiplier = math.random(0,100)
	for rowIndex, row in _mapGrid do
		if _delayRow then task.wait() end
		for columnIndex, hexagon in row do
			if _delayColumn then task.wait() end
			local currentPos = hexagon.Position
			
			--Use noise to provide random, more natural height differences.
			--Also uses the rowIndex and columnIndex to ensure that the heights are
			--	mostly smooth.
			--The largeScaleHeight is used to provide a more drastic change in height.
			local baseHeight = math.noise(rowIndex/10, columnIndex/10) * math.random(0, 20)
			local largeScaleHeight = math.noise(rowIndex/50, columnIndex/50) * randomLargeScaleMultiplier

			hexagon.Position = Vector3.new(
				currentPos.X, 
				baseHeight + largeScaleHeight + heightOffset, 
				currentPos.Z
			)
			
			if _visualizeGeneration then _parentHexagonToWorld(hexagon) end
		end
	end
end

--Checks if a specific grid has a neighboring grid with a specific biome type.
--This is useful for determining if something should be a rocky beach, or similar.
local function _hasNeighboringTileOfBiome(rowIndex, columnIndex, biome)
	for _, offset in _OFFSETS do 
		local neighborRow = rowIndex + offset[1]
		local neighborCol = columnIndex + offset[2]

		if _mapGrid[neighborRow] and _mapGrid[neighborRow][neighborCol] then
			if _mapGrid[neighborRow][neighborCol].Biome == biome then
				return true
			end
		end
	end
	return false
end

--Destroys any hexagons underneath the water.
--Also checks their heights and surrounding neighbors to determine
--	what type of biome they should be.
--The biome determines the color and material of a grid, and type of resources 
--	that can spawn there.
local function _cleanAndStyleHexagons()
	for rowIndex, row in _mapGrid do
		if _delayRow then task.wait() end
		for columnIndex, hexagon in row do
			if _delayColumn then task.wait() end
			local currentPos = hexagon.Position
			--Destroy the grid if it is under the water.
			if currentPos.Y <= 0.5 then
				hexagon:Destroy()
				_mapGrid[rowIndex][columnIndex] = nil
				continue
			end
			
			--Determines the biome types.
			--Uses math.random to make the transition from one biome
			--	to another more seamless rather than abrupt.
			if _hasSurroundingNil(rowIndex, columnIndex) then
				hexagon.Biome = BiomeTypes["Beach"]
			elseif currentPos.Y <= math.random(2,4) then
				hexagon.Biome = BiomeTypes["Desert"]
			elseif currentPos.Y >= math.random(45,50) then
				hexagon.Biome = BiomeTypes["Volcanic"]
			elseif currentPos.Y >= math.random(23,26) then
				hexagon.Biome = BiomeTypes["Snow"]
			elseif currentPos.Y >= math.random(16,19) then
				hexagon.Biome = BiomeTypes["Mountain"]
			elseif currentPos.Y >= math.random(10,13) then
				hexagon.Biome = BiomeTypes["FertileGrass"]
			else
				hexagon.Biome = BiomeTypes["Grass"]
			end
		end
	end
	
	--Important to split this function into two for loops because
	--	the following biomes are determined by whether or not their
	--	surrounding biomes are X
	--It needs the entire grid to already have biomes chosen.
	for rowIndex, row in _mapGrid do
		if _delayRow then task.wait() end
		for columnIndex, hexagon in row do
			if not hexagon then continue end
			if _delayColumn then task.wait() end
			local currentPos = hexagon.Position
			
			--If this grid is on the shore
			if _hasSurroundingNil(rowIndex, columnIndex) then
				--And it has a surrounding snow, mountain, or volcanic, then we want it to be
				--	a rocky beach, so there isnt any sand that is very high up.
				if _hasNeighboringTileOfBiome(rowIndex, columnIndex, BiomeTypes["Snow"]) then
					hexagon.Biome = BiomeTypes["RockyBeach"]
				elseif _hasNeighboringTileOfBiome(rowIndex, columnIndex, BiomeTypes["Mountain"]) then
					hexagon.Biome = BiomeTypes["RockyBeach"]
				elseif _hasNeighboringTileOfBiome(rowIndex, columnIndex, BiomeTypes["Volcanic"]) then
					hexagon.Biome = BiomeTypes["RockyBeach"]
				elseif currentPos.Y > 4 then
					if _hasNeighboringTileOfBiome(rowIndex, columnIndex, BiomeTypes["Mountain"]) or  
						_hasNeighboringTileOfBiome(rowIndex, columnIndex, BiomeTypes["Volcanic"]) or
						_hasNeighboringTileOfBiome(rowIndex, columnIndex, BiomeTypes["Snow"]) 
					then 
						hexagon.Biome = BiomeTypes["RockyBeach"]
					else
						hexagon.Biome = BiomeTypes["Grass"]
					end
				end
			end
			
			--Apply the biome appearance to the model
			--	and spawn a random resource.
			hexagon:UpdateAppearance()
			hexagon:SpawnResource()
			
			if _visualizeGeneration then _parentHexagonToWorld(hexagon) end
		end
	end
end

----------| Private Methods |----------

----------| Public Methods |----------
function MapService.GetMapGrid()
	return _mapGrid
end

function MapService.IsGenerating()
	return _generating
end

function MapService.GenerateMap(params)
	if _generating then return end
	_generating = true
	
	local randomSize = math.random(10,200)
	params = params or {}
	local gridLength = params.gridLength or randomSize
	local gridWidth = params.gridWidth or randomSize
	local heightOffset = params.heightOffset or math.random(-10,200)/10
	local smootheningPasses = params.smootheningPasses or math.random(2,3)

	MapService.DestroyMap()

	local hexWidth = HexTemplate.PrimaryPart.Size.X
	local hexLength = HexTemplate.PrimaryPart.Size.Z

	local centerX = gridWidth / 2
	local centerZ = gridLength / 2
	
	local islandRadius = (gridWidth + gridLength) / math.random(2,10)

	local startX = -(gridWidth * hexWidth) / 2
	local startZ = -(gridLength * (hexLength * 0.75)) / 2

	_createHexagonGrid(
		gridLength, gridWidth, 
		hexWidth, hexLength, 
		centerX, centerZ, 
		islandRadius, 
		startX, startZ
	)
	_assignHexagonHeights(heightOffset)
	_smoothenGrid(smootheningPasses)
	_cleanAndStyleHexagons()
	_parentMapToWorld()
	
	SendMapGridEvent:FireAllClients(_mapGrid)
	
	print("Done generating!")
	
	--If the entire 2D array is nil then regenerate the map
	if _entireGridNil() then
		_generating = false
		MapService.GenerateMap()
	else
		_generating = false
	end
end

-- Loops through and Destroys every hexagon.
function MapService.DestroyMap()
	for rowIndex, row in _mapGrid do
		if _delayRow then task.wait() end
		for columnIndex, hexagon in row do
			if _delayColumn then task.wait() end
			if hexagon then
				hexagon:Destroy()
				_mapGrid[rowIndex][columnIndex] = nil
			end
		end
	end
	_mapGrid = {}
end

-- Start method for use in module loader.
function MapService.Start()
	--Setup map initially
	MapService.GenerateMap({
		gridLength = 25,
		gridWidth = 25,
		heightOffset = 1
	})
	
	--Setup Event Listeners
	game.Workspace.Button.ClickDetector.MouseClick:Connect(function()
		MapService.GenerateMap()
	end)
end

----------| Return |----------
return MapService
