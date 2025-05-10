-- PathfindingServiceV2
local PathfindingServiceV2 = {}

-- Enum-like status for pathfinding results
PathfindingServiceV2.PathStatus = {
    Complete = "Complete",
    NoPath = "NoPath",
    Partial = "Partial"
}

-- Node for A* pathfinding
local function CreateNode(position, parent, g, h)
    return {
        Position = position,
        Parent = parent,
        G = g, -- Cost from start
        H = h, -- Heuristic to goal
        F = g + h -- Total cost
    }
end

-- Check if a position is walkable (raycast-based collision detection)
local function IsWalkable(position, agentRadius, agentHeight)
    local ray = Ray.new(position + Vector3.new(0, agentHeight / 2, 0), Vector3.new(0, -agentHeight, 0))
    local hit, hitPos = workspace:FindPartOnRayWithIgnoreList(ray, {workspace.Terrain})
    return not hit or (position.Y - hitPos.Y) < 1 -- Grounded or small step
end

-- Get neighbors for a node (8-directional grid with jump/climb checks)
local function GetNeighbors(position, agentRadius, agentHeight, agentCanJump)
    local neighbors = {}
    local directions = {
        Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
        Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1)
    }
    for _, dir in pairs(directions) do
        local newPos = position + dir * agentRadius
        if IsWalkable(newPos, agentRadius, agentHeight) then
            table.insert(neighbors, newPos)
        end
        if agentCanJump then
            local jumpPos = newPos + Vector3.new(0, agentHeight, 0)
            if IsWalkable(jumpPos, agentRadius, agentHeight) then
                table.insert(neighbors, jumpPos)
            end
        end
    end
    return neighbors
end

function PathfindingServiceV2:CreatePath(params)
    local path = {
        AgentRadius = params.AgentRadius or 2,
        AgentHeight = params.AgentHeight or 5,
        AgentCanJump = params.AgentCanJump or true,
        AgentCanClimb = params.AgentCanClimb or true,
        Status = PathfindingServiceV2.PathStatus.NoPath,
        Waypoints = {},
        ComputeAsync = function(self, startPos, endPos)
            -- A* Pathfinding Implementation
            local openSet = {}
            local closedSet = {}
            local startNode = CreateNode(startPos, nil, 0, (endPos - startPos).Magnitude)
            openSet[startNode.Position] = startNode

            while next(openSet) do
                -- Find node with lowest F score
                local current
                local lowestF = math.huge
                for _, node in pairs(openSet) do
                    if node.F < lowestF then
                        lowestF = node.F
                        current = node
                    end
                end

                if not current then break end

                -- Move to closed set
                openSet[current.Position] = nil
                closedSet[current.Position] = current

                -- Goal reached
                if (current.Position - endPos).Magnitude < self.AgentRadius then
                    local waypoints = {}
                    while current do
                        table.insert(waypoints, 1, {
                            Position = current.Position,
                            Action = (current.Position.Y > (current.Parent and current.Parent.Position.Y or current.Position.Y)) and "Jump" or "Walk"
                        })
                        current = current.Parent
                    end
                    self.Waypoints = waypoints
                    self.Status = PathfindingServiceV2.PathStatus.Complete
                    return
                end

                -- Check neighbors
                for _, neighborPos in pairs(GetNeighbors(current.Position, self.AgentRadius, self.AgentHeight, self.AgentCanJump)) do
                    if not closedSet[neighborPos] then
                        local g = current.G + (neighborPos - current.Position).Magnitude
                        local h = (endPos - neighborPos).Magnitude
                        local neighbor = openSet[neighborPos] or CreateNode(neighborPos, current, g, h)

                        if not openSet[neighborPos] or g < neighbor.G then
                            neighbor.G = g
                            neighbor.H = h
                            neighbor.F = g + h
                            neighbor.Parent = current
                            openSet[neighborPos] = neighbor
                        end
                    end
                end
            end

            self.Status = PathfindingServiceV2.PathStatus.NoPath
        end,
        GetWaypoints = function(self)
            return self.Waypoints
        end
    }
    return path
end

return PathfindingServiceV2