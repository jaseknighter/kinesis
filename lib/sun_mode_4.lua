local sun_mode_4 = {}

------------------------------------------
-- Initialization and deinitialization
------------------------------------------
function sun_mode_4.init(self)
  -- Set variables needed for mode 4 code
  self.active_photons = {1}
  self.wait_clock = nil
  self.velocity_deltas = {}
  self.sun_pulsing = false
  self.sun_pulse_phase = 0
  self.sun_pulse_speed = 0.2
  self.previous_input_direction = 0
  self.reversed = false
  self.recently_reversed = false
  self.preview_speed = false
  self.sun_level_base = 10
  self.sun_level = self.sun_level_base

  -- Assign callbacks (defined below) to handle events when a photon or ray changes
  self.photon_changed_callback  = sun_mode_4.photon_changed
  self.ray_changed_callback     = sun_mode_4.ray_changed
  

  self:update_state()

  -- Deinit (cleanup) function
  self.deinit = function()
    print("deinit sun mode: 4")
  end  

end

-- [[ 0_0 ]] --
function sun_mode_4.key(self, n, z)
  -- Do something when a key is pressed
end

function sun_mode_4.enc(self, n, delta)
  if n==1 then return end
  sun_mode_4.set_speed(self,delta)
  
end

-- Sets the speed and direction of the photons
-- Checks to see if the photon movement should stop due to direction changing
-- Then calls set_velocity 
function sun_mode_4.set_speed(self,delta)
  local input_direction = sign(delta)
  if input_direction ~= self.previous_input_direction and self.previous_input_direction ~= 0 then
    -- print("reverse direction")
    if self.motion_clock then
      clock.cancel(self.motion_clock)
      self.motion_clock = nil
    end
    if self.wait_clock then
      clock.cancel(self.wait_clock)
      self.wait_clock = nil
    end

    self.velocity = 0
    self.direction = 0
    self.sun_pulsing = false
    self.preview_speed = false
    self.velocity_deltas = {}
    self.reversed = true
    self.recently_reversed = true
    self.previous_input_direction = input_direction

    clock.run(function()
      clock.sleep(0.5)
      self.recently_reversed = false
    end)
    return
  end

  if self.recently_reversed then
    -- print("recently reversed")
    return
  end

  if self.reversed then
    self.reversed = false
    self.velocity_deltas = {}
  end

  self.previous_input_direction = input_direction
  sun_mode_4.set_velocity(self,delta)
end

function sun_mode_4.set_velocity(self,delta)
    local now = util.time()
    table.insert(self.velocity_deltas, {delta = delta, time = now})
  
    self.preview_speed = true
    self.sun_pulsing = true
  
    if #self.velocity_deltas >= 2 then
      local total_delta = 0
      for _, e in ipairs(self.velocity_deltas) do
        total_delta = total_delta + e.delta
      end
      local duration = math.max(now - self.velocity_deltas[1].time, 0.01)
      local velocity = total_delta / duration
      self.sun_pulse_speed = util.clamp(math.abs(velocity) * 0.01, 0.05, 2.0)
    end
  
    if self.wait_clock then clock.cancel(self.wait_clock) end
  
    self.wait_clock = clock.run(function()
      clock.sleep(0.5)
      if #self.velocity_deltas == 0 then
        self.preview_speed = false
        return
      end
  
      local total_delta = 0
      for _, e in ipairs(self.velocity_deltas) do
        total_delta = total_delta + e.delta
      end
      local duration = math.max(self.velocity_deltas[#self.velocity_deltas].time - self.velocity_deltas[1].time, 0.01)
      local new_velocity = total_delta / duration
      local new_direction = sign(new_velocity)
  
      self.velocity_deltas = {}
      self.wait_clock = nil
      self.preview_speed = false
  
      if math.abs(new_velocity) < 0.01 then
        self.velocity = 0
        self.direction = 0
        self.sun_pulsing = false
        return
      end
  
      self.velocity = new_velocity
      self.direction = new_direction
      self.sun_pulsing = false
      self.reversed = false
  
      if not self.motion_clock then
        self.motion_clock = clock.run(function()
          while true do
            clock.sleep(1 / math.abs(self.velocity))
            self:set_active_photons_rel(self.direction)
          end
        end)
      end
    end)
end

function sun_mode_4.draw_sun_pulsing(self)
  local sun_pulse_amp = 5
  self.sun_pulse_phase = (self.sun_pulse_phase + self.sun_pulse_speed) % (2 * math.pi)
  local sun_pulse = math.sin(self.sun_pulse_phase) * sun_pulse_amp
  self.sun_level = util.clamp(self.sun_level_base + sun_pulse, 0, MAX_LEVEL)
end

-- [[ 0_0 ]] --
function sun_mode_4.photon_changed(self,ray_id,photon_id)
  -- Do something when the photon changes
  -- print("photon changed: sun/ray/photon: ",self.index,ray_id,photon_id)
end

-- [[ 0_0 ]] --
function sun_mode_4.ray_changed(self,ray_id,photon_id)
  -- Do something when the ray changes
  -- print(">>>ray changed: sun/ray/photon: ",self.index,ray_id,photon_id)
end

-- [[ 0_0 ]] --
function sun_mode_4.redraw(self)
  if self.sun_pulsing or self.preview_speed then
    sun_mode_4.draw_sun_pulsing(self)
  elseif not self.sun_pulsing then
    self.sun_level = self.sun_level_base
  end  
    -- Draw something here specific to sun mode 4
end

return sun_mode_4
