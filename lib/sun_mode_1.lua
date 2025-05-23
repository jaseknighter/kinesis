-- Sun mode 1: Softcut
-- Reference: https://monome.org/docs/norns/softcut/ 

local sun_mode_1 = {}

------------------------------------------
-- Initialization and deinitialization
-- Note: the init function for each sun mode receives a reference to the sun unitializing it (self)
------------------------------------------
function sun_mode_1.init(self)
  -- Set callbacks for changes in active photon/ray
  self.photon_changed_callback  = sun_mode_1.photon_changed
  self.ray_changed_callback     = sun_mode_1.ray_changed

  -- Variables for rotating the active photons 
  self.active_photons = {1}
  self.wait_clock = nil
  self.velocity_deltas = {}
  self.sun_pulsing = false
  self.sun_pulse_phase = 0
  self.sun_pulse_speed = 0.2
  self.cut_previous_input_direction = 0
  self.reversed = false
  self.cut_recently_reversed = false
  self.cut_preview_speed = false
  self.sun_level_base = 10
  self.sun_level = self.sun_level_base

  -- Initialize softcut and supporting variables   
  self.cut_voice   =  self.index
  self.cut_rate      =  1
  self.cut_rec       =  0.2 --0.5
  self.cut_pre       =  0 --0.5
  self.cut_slew      =  0.1
  self.cut_loop_end  =  3
  sun_mode_1.init_softcut(self)   

  self:update_state()

  -- Deinit (cleanup) function
  self.deinit = function()
    print("deinit sun mode: 1")
    softcut.buffer_clear_channel(self.index)
    softcut.enable(1,0)
    sun_mode_1.set_velocity(self,0)
  end
end

function sun_mode_1.init_softcut(self)
  print("init softcut")
  
  audio.level_adc_cut(0)
  audio.level_eng_cut(1)
  
  softcut.enable(self.cut_voice,1)                        -- voice, state
  softcut.buffer(self.cut_voice,1)                        -- voice, buffer
  softcut.level(self.cut_voice,1)                         -- voice, level
  softcut.rate(1,self.cut_rate)                           -- voice, rate
  softcut.loop(self.cut_voice,1)                          -- voice, state
  softcut.position(self.cut_voice,1)                      -- voice, position
  softcut.loop_start(self.cut_voice,1)                    -- voice, start
  softcut.loop_end(self.cut_voice,self.cut_loop_end)      -- voice, end
  softcut.play(self.cut_voice,1)                          -- voice, play
  softcut.level_input_cut(1,self.cut_voice,1.0)           -- channel, voice, amp
  softcut.level_input_cut(2,self.cut_voice,1.0)           -- channel, voice, amp
  softcut.rec_level(self.cut_voice,self.cut_rec)          -- voice, record level
  softcut.pre_level(self.cut_voice,self.cut_pre)          -- voice, prelevel
  softcut.rec(self.cut_voice,1)                           -- voice, state                     
  softcut.rate_slew_time (self.cut_voice, self.cut_slew)  -- voice, slew time
end

function sun_mode_1.key(self, n, z)
  -- 0_0 -- Do something when a key is pressed
end

function sun_mode_1.enc(self, n, delta)
  if n==1 then return end
  sun_mode_1.set_speed(self,delta)
end

-- Set the speed and direction of the photons
function sun_mode_1.set_speed(self,delta)
  local input_direction = sign(delta)
  
  -- Check to see if the photon movement should stop due to direction changing
  if input_direction ~= self.cut_previous_input_direction and self.cut_previous_input_direction ~= 0 then
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
    self.cut_preview_speed = false
    self.velocity_deltas = {}
    self.reversed = true
    self.cut_previous_input_direction = input_direction
    
    -- Set cut_recently_reversed to true for 0.5 seconds
    self.cut_recently_reversed = true
    clock.run(function()
      clock.sleep(0.5)
      self.cut_recently_reversed = false
    end)
    return
  end
  
  -- If cut_recently_reversed is true, break out of this code (this prevents velocity from being set)
  if self.cut_recently_reversed then
    -- print("recently reversed")
    return
  end

  if self.reversed then
    self.reversed = false
    self.velocity_deltas = {}
  end

  self.cut_previous_input_direction = input_direction
  sun_mode_1.set_velocity(self,delta)
end

function sun_mode_1.set_velocity(self,delta)
    local now = util.time()
    table.insert(self.velocity_deltas, {delta = delta, time = now})
  
    self.cut_preview_speed = true
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
        self.cut_preview_speed = false
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
      self.cut_preview_speed = false
  
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

function sun_mode_1.draw_sun_pulsing(self)
  local sun_pulse_amp = 5
  self.sun_pulse_phase = (self.sun_pulse_phase + self.sun_pulse_speed) % (2 * math.pi)
  local sun_pulse = math.sin(self.sun_pulse_phase) * sun_pulse_amp
  self.sun_level = util.clamp(self.sun_level_base + sun_pulse, 0, MAX_LEVEL)
end

function sun_mode_1.redraw(self)
    if self.sun_pulsing or self.cut_preview_speed then
      sun_mode_1.draw_sun_pulsing(self)
    elseif not self.sun_pulsing then
      self.sun_level = self.sun_level_base
    end  
end

-- Callbacks

-- [[ 0_0 ]] -- If a new photon has been highlighted do someting
function sun_mode_1.photon_changed(self,ray_id,photon_id)
  -- print("photon_changed in mode 1",self.index,ray_id,photon_id)
end

-- [[ 0_0 ]] -- If a new ray has been highlighted do someting
function sun_mode_1.ray_changed(self,ray_id,photon_id)
  -- print("ray_changed in mode 1",self.index,ray_id,photon_id)
  if ray_id%2 == 0 then
    self.cut_rate = self.cut_rate == 1 and math.random()*5 or 1 
    softcut.rate(self.cut_voice,self.cut_rate)
  end
end


return sun_mode_1
