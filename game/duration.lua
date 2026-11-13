-- The LuaDurationObject C_DurationUtil.CreateDuration hands out (api/<flavor>/LuaDurationObjectAPI.lua): a time span on
-- the GetTime clock with a mod rate. Blizzard's aura buttons set one from an aura's expiration time, duration and time
-- mod. The Evaluate*, Format* and clock methods are left out until a caller needs them.
local M = {}

local Duration = {}
Duration.__index = Duration

-- Enum.DurationTimeModifier: RealTime (0) is seconds on the clock, BaseTime (1) is seconds before the mod rate.
local BASE_TIME = 1

-- now() is the clock's current time (the world's GetTime).
function M.new(now)
  return setmetatable({ now = now, startTime = 0, endTime = 0, modRate = 1 }, Duration)
end

-- source: assumed (row G85) a mod rate above 1 shortens the span on the clock: duration / modRate real seconds, as
-- CooldownFrame_Set's modRate does.
function Duration:SetTimeFromEnd(endTime, duration, modRate)
  self.modRate = modRate or 1
  self.startTime, self.endTime = endTime - duration / self.modRate, endTime
end

function Duration:SetTimeFromStart(startTime, duration, modRate)
  self.modRate = modRate or 1
  self.startTime, self.endTime = startTime, startTime + duration / self.modRate
end

function Duration:SetTimeSpan(startTime, endTime)
  self.startTime, self.endTime, self.modRate = startTime, endTime, 1
end

function Duration:Reset()
  self:SetTimeSpan(0, 0)
end

Duration.SetToDefaults = Duration.Reset

function Duration:Assign(other)
  self.startTime, self.endTime, self.modRate = other.startTime, other.endTime, other.modRate
end

function Duration:Copy()
  local copy = M.new(self.now)
  copy:Assign(self)
  return copy
end

local function scaled(self, seconds, modifier)
  return modifier == BASE_TIME and seconds * self.modRate or seconds
end

function Duration:GetStartTime()
  return self.startTime
end

function Duration:GetEndTime()
  return self.endTime
end

function Duration:GetModRate()
  return self.modRate
end

function Duration:GetTotalDuration(modifier)
  return scaled(self, self.endTime - self.startTime, modifier)
end

function Duration:GetElapsedDuration(modifier)
  local elapsed = math.min(math.max(self.now() - self.startTime, 0), self.endTime - self.startTime)
  return scaled(self, elapsed, modifier)
end

function Duration:GetRemainingDuration(modifier)
  return scaled(self, math.max(self.endTime - math.max(self.now(), self.startTime), 0), modifier)
end

-- source: assumed (row G85) a zero span is 0% elapsed and 0% remaining.
function Duration:GetElapsedPercent()
  local total = self.endTime - self.startTime
  return total > 0 and self:GetElapsedDuration() / total or 0
end

function Duration:GetRemainingPercent()
  local total = self.endTime - self.startTime
  return total > 0 and self:GetRemainingDuration() / total or 0
end

function Duration:IsZero()
  return self.endTime - self.startTime <= 0
end

function Duration:HasStarted()
  return self.now() >= self.startTime
end

function Duration:HasExpired()
  return self.now() >= self.endTime
end

function Duration:IsActive()
  return self:HasStarted() and not self:HasExpired()
end

-- source: assumed (row G85) the kit's durations hold no secrets.
function Duration:HasSecretValues()
  return false
end

return M
