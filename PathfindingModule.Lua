-- PathfindingModule
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local PathfindingServiceV2 = require(ServerScriptService.PathfindingServiceV2) -- Updated path

local PathModule = {}

-- Settings
local RECOMPUTE_INTERVAL = 0.5 -- Faster updates for smoother movement
local WAYPOINT_THRESHOLD = 1.5 -- Tighter threshold for precision
local ATTACK_RANGE = 5 -- Hostile attack range
local WANDER_ZONE_RADIUS = 30 -- Friendly wander zone size
local BATCH_SIZE = 50 -- Process NPCs in batches for performance
local NPC_UPDATE_RATE = 1/30 -- Update NPCs at 30 FPS

-- Global NPC management for batching
local activeNPCs = {}
local lastBatchUpdate = 0

function PathModule.new(npc, mode, targetPoints, wanderZoneCenter)
    local self = setmetatable({}, {__index = PathModule})
    self.NPC = npc
    self.Humanoid = npc:FindFirstChildOfClass("Humanoid")
    self.HRP = npc:FindFirstChild("HumanoidRootPart")
    self.Mode = mode
    self.Targets = targetPoints or {}
    self.WanderZoneCenter = wanderZoneCenter or (self.HRP and self.HRP.Position) or Vector3.new(0, 0, 0)
    self.CurrentPath = nil
    self.Waypoints = {}
    self.CurrentWaypointIndex = 1
    self.LastRecompute = 0
    self.Moving = false
    self.CurrentTarget = nil
    self.AttackCooldown = 0
    self.IsAttacking = false

    -- Register NPC for batch updates
    table.insert(activeNPCs, self)

    function self:ComputePath(targetPos)
        if not self.HRP then return end
        local path = PathfindingServiceV2:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = true
        })

        path:ComputeAsync(self.HRP.Position, targetPos)
        if path.Status == PathfindingServiceV2.PathStatus.Complete then
            self.CurrentPath = path
            self.Waypoints = path:GetWaypoints()
            self.CurrentWaypointIndex = 1
        else
            self.CurrentPath = nil
        end
    end

    function self:MoveToNextWaypoint()
        if not self.CurrentPath or not self.Humanoid then return end
        local waypoint = self.Waypoints[self.CurrentWaypointIndex]
        if waypoint then
            if waypoint.Action == "Jump" and self.Humanoid.JumpPower > 0 then
                self.Humanoid.Jump = true
            end
            self.Humanoid:MoveTo(waypoint.Position)
        end
    end

    function self:OnReachedWaypoint()
        self.CurrentWaypointIndex += 1
        if self.CurrentWaypointIndex <= #self.Waypoints then
            self:MoveToNextWaypoint()
        else
            self.Moving = false
        end
    end

    function self:Attack(target)
        if not self.IsAttacking and tick() - self.AttackCooldown > 1 then
            self.IsAttacking = true
            self.AttackCooldown = tick()
            -- Basic attack: deal damage to target
            local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
            if targetHumanoid then
                targetHumanoid:TakeDamage(10) -- Adjustable damage
            end
            task.wait(0.5) -- Attack animation/delay
            self.IsAttacking = false
        end
    end

    function self:Update()
        if not self.HRP or not self.Humanoid or self.Humanoid.Health <= 0 then
            self:Destroy()
            return
        end

        if self.Mode == "Hostile" then
            local nearestPlayer, dist = nil, math.huge
            for _, player in pairs(game.Players:GetPlayers()) do
                local char = player.Character
                if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChildOfClass("Humanoid").Health > 0 then
                    local d = (char.HumanoidRootPart.Position - self.HRP.Position).Magnitude
                    if d < dist then
                        nearestPlayer = char
                        dist = d
                    end
                end
            end

            if nearestPlayer then
                self.CurrentTarget = nearestPlayer
                if dist <= ATTACK_RANGE then
                    self:Attack(nearestPlayer)
                    self.Moving = false
                elseif tick() - self.LastRecompute > RECOMPUTE_INTERVAL then
                    self:ComputePath(nearestPlayer.HumanoidRootPart.Position)
                    self.LastRecompute = tick()
                end
            else
                self.Moving = false
            end

        elseif self.Mode == "MoveToPoints" then
            if not self.CurrentTarget or not self.CurrentTarget:IsDescendantOf(workspace) then
                self.CurrentTarget = self.Targets[math.random(1, #self.Targets)]
                self:ComputePath(self.CurrentTarget.Position)
            end

        elseif self.Mode == "Friendly" then
            if tick() - self.LastRecompute > 5 then
                -- Wander within zone
                local wanderOffset = Vector3.new(
                    math.random(-WANDER_ZONE_RADIUS, WANDER_ZONE_RADIUS),
                    0,
                    math.random(-WANDER_ZONE_RADIUS, WANDER_ZONE_RADIUS)
                )
                local newPos = self.WanderZoneCenter + wanderOffset
                if (newPos - self.WanderZoneCenter).Magnitude <= WANDER_ZONE_RADIUS then
                    self:ComputePath(newPos)
                    self.LastRecompute = tick()
                end
            end
        end

        -- Movement logic
        if self.CurrentPath and self.Waypoints[self.CurrentWaypointIndex] and not self.IsAttacking then
            local dist = (self.HRP.Position - self.Waypoints[self.CurrentWaypointIndex].Position).Magnitude
            if dist < WAYPOINT_THRESHOLD then
                self:OnReachedWaypoint()
            elseif not self.Moving then
                self.Moving = true
                self:MoveToNextWaypoint()
            end
        end
    end

    function self:Destroy()
        -- Remove from active NPCs
        for i, npc in ipairs(activeNPCs) do
            if npc == self then
                table.remove(activeNPCs, i)
                break
            end
        end
    end

    return self
end

-- Batch update system for performance
RunService.Heartbeat:Connect(function()
    if tick() - lastBatchUpdate < NPC_UPDATE_RATE then return end
    lastBatchUpdate = tick()

    -- Process NPCs in batches
    for i = 1, #activeNPCs, BATCH_SIZE do
        local batch = {unpack(activeNPCs, i, math.min(i + BATCH_SIZE - 1, #activeNPCs))}
        for _, npc in ipairs(batch) do
            npc:Update()
        end
    end
end)

return PathModule