-- lib/sun_mode_2.lua 
-- this mode uses the reflection library
-- Reference: https://monome.org/docs/norns/reference/lib/reflection

-- note about the "event router" (defined below)
--  events generated by the reflection library
--  are consolidated in an event router.
--  connect reflection events to functions
--  for controlling sounds through this router

local sun_mode_2 = {}

-- define state names.
local states = {'r','p','l'}  -- record, play, loop

------------------------------------------
-- initialization and deinitialization
------------------------------------------
function sun_mode_2.init(self)
  self.reflection_indices = {}
  self.max_cursor = 8 * 16
  self.state = 1  -- 1 = record, 2 = play, 3 = loop

  -- define which rays have reflectors
  if self.index == 1 then
    self.reflector_locations = {1,5,9,13}
  else
    self.reflector_locations = {3,7,11,15}
  end

  -- set the selected reflector
  self.selected_ray = self.reflector_locations[1]

  -- initialize state tables (keyed by reflector id)
  self.record   = {}
  self.play     = {}
  self.loop     = {}
  for i = 1, #self.reflector_locations do
    local rid = self.reflector_locations[i]
    self.record[rid]  = 0
    self.play[rid]    = 1
    self.loop[rid]    = 1
    sun_mode_2.deselect_reflector(self, rid)
  end

  sun_mode_2.init_reflectors(self)
  sun_mode_2.hide_non_reflector_rays(self)
  
  -- select the initial reflector
  sun_mode_2.select_reflector(self, self.selected_ray)

  sun_mode_2.init_sounds(self)

  -- define a deinit function to
  --   remove any variables or tables that might stick around
  --   after switching to a different sun mode
  --   for example: a lattice or reflection instance
  self.deinit = function()
    print("deinit sun mode: 2")
    self.lattice:stop()
    self.lattice = nil
    for reflector=1,#self.reflectors do
      self.reflectors[reflector]:stop()
      self.reflectors[reflector]:clear()
    end
    self.deinit = nil
  end  
end

------------------------------------------
-- helpers;
------------------------------------------
function sun_mode_2.hide_non_reflector_rays(self)
  for ray = 1, NUM_RAYS do
    if not table_contains(self.reflector_locations, ray) then
      self:set_ray_brightness(ray, 0)
    end
  end
end

------------------------------------------
-- get minimum brightness for a reflector
------------------------------------------
function sun_mode_2.get_MIN_LEVEL(self, reflector_id)
  local min_l = 0
  for i = 1, #self.reflector_locations do
    if reflector_id == self.reflector_locations[i] then
      min_l = 3
      break
    end
  end
  return min_l
end

------------------------------------------
-- get the next reflector from reflector_locations
------------------------------------------
function sun_mode_2.get_next_ray(self, delta)
  local current_index = nil
  for i = 1, #self.reflector_locations do
    if self.selected_ray == self.reflector_locations[i] then
      current_index = i
      break
    end
  end
  if not current_index then current_index = 1 end
  local next_index = util.wrap(current_index + delta, 1, #self.reflector_locations)
  return self.reflector_locations[next_index]
end

------------------------------------------
-- encoder handler
------------------------------------------
function sun_mode_2.enc(self, n, delta)
  if n == 1 then
    self.state = util.clamp(self.state + delta, 1, #states)
  else
    if alt_key == true then
      -- Change the selected reflector.
      sun_mode_2.deselect_reflector(self, self.selected_ray)
      self.selected_ray = sun_mode_2.get_next_ray(self, delta)
      sun_mode_2.select_reflector(self, self.selected_ray)
      sun_mode_2.draw_reflector_cursor(self, self.selected_ray)
    else
      -- Adjust reflector cursor for the selected reflector.
      sun_mode_2.set_reflector_cursor_rel(self, self.selected_ray, delta)
      sun_mode_2.draw_reflector_cursor(self, self.selected_ray)
    end
  end
end

------------------------------------------
-- key handler
------------------------------------------
function sun_mode_2.key(self, n, z)
  local reflector_id = self.selected_ray
  if self.state == 1 then  -- record state
    if self.record[reflector_id] == 1 and z == 0 then
      self.record[reflector_id] = 0
      self.reflectors[reflector_id]:set_rec(0)
      print("key: stop reflector recording")
    
      -- tab.print(self.reflectors[reflector_id].event_prev)
    elseif self.record[reflector_id] == 0 and z == 0 then
      print("key: start reflector recording",reflector_id,self.reflectors[reflector_id])
      self.record[reflector_id] = 1
      self.reflectors[reflector_id]:clear()
      self.reflectors[reflector_id]:set_rec(1)
      tab.print(self.reflectors[reflector_id].event_prev)
    end
  elseif self.state == 2 then -- play state
    if z == 0 then
      if n == 2 then
        if self.play[reflector_id] == 1 then
          self.play[reflector_id] = 0
          print("toggle_play: stop reflector playing", reflector_id)
          if self.reflectors[reflector_id] and self.reflectors[reflector_id].stop then
            self.reflectors[reflector_id]:stop()
          end
        else
          self.play[reflector_id] = 1
          print("toggle_play: start reflector playing", reflector_id)
          if self.reflectors[reflector_id] and self.reflectors[reflector_id].start then
            self.reflectors[reflector_id]:start()
          end
        end
      end
    end
  elseif self.state == 3 then  -- loop state
    if self.loop[reflector_id] == 1 and z == 0 then
      self.loop[reflector_id] = 0
      print("key: stop reflector looping")
      self.reflectors[reflector_id]:set_loop(0)
    elseif self.loop[reflector_id] == 0 and z == 0 then
      self.loop[reflector_id] = 1
      print("key: start reflector looping")
      self.reflectors[reflector_id]:set_loop(1)
    end
  end
end

------------------------------------------
-- get last selected photon for a reflector
------------------------------------------
function sun_mode_2.get_last_selected_photon(self, reflector_id)
  local last_ph, last_ph_brightness
  if self.reflection_indices[reflector_id] then
    local cursor = self.reflection_indices[reflector_id].reflection_cursor
    local q, r = quotient_remainder(cursor, NUM_RAYS)
    last_ph = q + 1
    last_ph_brightness = r * NUM_RAYS
    if last_ph_brightness == 1 then last_ph_brightness = 0 end
  end
  return last_ph, last_ph_brightness
end

------------------------------------------
-- calculate photon brightness for a reflector
------------------------------------------
function sun_mode_2.get_photon_brightness(self, reflector_id, photon)
  local brightness, last_ph, last_ph_brightness
  if self.reflection_indices[reflector_id] then
    last_ph, last_ph_brightness = sun_mode_2.get_last_selected_photon(self, reflector_id)
    if photon < last_ph then
      brightness = MAX_LEVEL
    elseif photon == last_ph then
      brightness = last_ph_brightness
    else
      brightness = sun_mode_2.get_MIN_LEVEL(self, reflector_id)
    end
  else
    brightness = sun_mode_2.get_MIN_LEVEL(self, reflector_id)
  end
  return brightness, last_ph
end

------------------------------------------
-- draw the reflector cursor for a given reflector
------------------------------------------
function sun_mode_2.draw_reflector_cursor(self, reflector_id)
  local brightness_fn = function(photon_id,photon)
    local brightness = sun_mode_2.get_photon_brightness(self, reflector_id, photon_id)
    photon:set_brightness(brightness)
    return nil
  end
  self:set_ray_brightness(reflector_id,brightness_fn)
end

------------------------------------------
-- set reflector cursor (absolute)
------------------------------------------
function sun_mode_2.set_reflector_cursor(self, reflector_id, val)
  if not self.reflection_indices[reflector_id] then
    self.reflection_indices[reflector_id] = { reflection_cursor = 1 }
  end
  
  self.reflection_indices[reflector_id].reflection_cursor = val
  sun_mode_2.draw_reflector_cursor(self, reflector_id)
end

------------------------------------------
-- set reflector cursor (relative)
------------------------------------------
function sun_mode_2.set_reflector_cursor_rel(self, reflector_id, delta)
  if not self.reflection_indices[reflector_id] then
    self.reflection_indices[reflector_id] = { reflection_cursor = 1 }
  end
  local cursor = self.reflection_indices[reflector_id].reflection_cursor
  local new_cursor = util.clamp(cursor + delta, 1, self.max_cursor)
  self.reflection_indices[reflector_id].reflection_cursor = new_cursor
  -- Store reflector data.
  local new_data = { reflector = reflector_id, value = new_cursor }
  sun_mode_2.store_reflector_data(self, reflector_id, new_data)

  -- pass the event value to the router
  sun_mode_2.event_router(self, reflector_id, "process", new_data.value)

end

------------------------------------------
-- deselect a reflector
------------------------------------------
function sun_mode_2.deselect_reflector(self, reflector_id)
  self:set_ray_brightness(reflector_id,function() 
    return sun_mode_2.get_MIN_LEVEL(self, reflector_id)
  end)
end

------------------------------------------
-- select a reflector
------------------------------------------
function sun_mode_2.select_reflector(self, reflector_id)
  -- First, hide all non-reflector rays.
  sun_mode_2.hide_non_reflector_rays(self)
  -- Then update the display for the selected reflector.
  local set_reflector_brightness = function(photon_id, photon)
    if sun_mode_2.ray_has_cursor(self) then
      sun_mode_2.draw_reflector_cursor(self, reflector_id)
    end
    if photon_id < PHOTONS_PER_RAY then
      return MIN_LEVEL
    else
      local brightness = sun_mode_2.get_photon_brightness(self, reflector_id, photon_id)
      photon:morph_photon(MAX_LEVEL, brightness, 1, 15, 'lin', nil, reflector_id)
      return nil
    end
  end
  self:set_ray_brightness(reflector_id,set_reflector_brightness)
  -- for photon = 1, PHOTONS_PER_RAY do
    -- local p = self:get_photon(reflector_id, photon)
    -- if photon < PHOTONS_PER_RAY then
    --   p:set_brightness(MIN_LEVEL)
    -- else
    --   local brightness = sun_mode_2.get_photon_brightness(self, reflector_id, photon)
    --   local morphing_callback = function(next_val, done)
    --   end
    --   p:morph_photon(15, brightness, 1, 15, 'lin', morphing_callback, reflector_id)
    -- end
    -- if sun_mode_2.ray_has_cursor(self) then
    --   sun_mode_2.draw_reflector_cursor(self, reflector_id)
    -- end
  -- end
end

------------------------------------------
-- check if the currently selected reflector has cursor data
------------------------------------------
function sun_mode_2.ray_has_cursor(self)
  return self.reflection_indices[self.selected_ray] ~= nil
end

------------------------------------------
-- calculate pointer position (for display)
------------------------------------------
function sun_mode_2.calc_pointer_position(self)
  local center_x = (self.index == 1) and 32 or 96
  local center_y = 32
  local angle = -math.pi/2 + (self.selected_ray - 1) * (2 * math.pi / NUM_RAYS)
  local distance = SUN_RADIUS - 1
  local x = util.round(center_x + distance * math.cos(angle))
  local y = util.round(center_y + distance * math.sin(angle))
  return x, y
end

------------------------------------------
-- redraw routine.
------------------------------------------
function sun_mode_2.redraw(self)
  local x = (self.index == 1) and 1 or 65
  local y = 62
  screen.move(x, y)
  screen.rect(x, y-5, 18, 8)
  screen.level(0)
  screen.fill()
  
  screen.move(x, y)
  screen.level(3)
  local state_text = tostring(self.selected_ray)
  if self.state == 1 then
    local rec = (self.record[self.selected_ray] == 0) and "-" or "+"
    state_text = state_text .. states[self.state] .. rec
  elseif self.state == 2 then
    local play = (self.play[self.selected_ray] == 0) and "-" or "+"
    state_text = state_text .. states[self.state] .. play
  elseif self.state == 3 then
    local loop = (self.loop[self.selected_ray] == 0) and "-" or "+"
    state_text = state_text .. states[self.state] .. loop
  end
  screen.text(state_text)

  local point_x, point_y = sun_mode_2.calc_pointer_position(self)
  screen.level(0)
  screen.circle(point_x, point_y, 2)
  screen.fill()
end

------------------------------------------
------------------------------------------
--      reflection code       --
------------------------------------------
------------------------------------------
function sun_mode_2.store_reflector_data(self, reflector_id, data)
  if self.reflectors[reflector_id] then
    -- print("store reflector data",reflector_id,self.reflectors[reflector_id],data.reflector,data.value)
    self.reflectors[reflector_id]:watch{
      reflector = data.reflector,
      value = data.value
    }
  else
    print("can't store reflector data",reflector_id,self.reflectors[reflector_id])

  end
end

function sun_mode_2.init_reflectors(self)
  self.reflectors = {}
  self.reflector_data = {}
  self.reflector_processors = {}

  for i = 1, #self.reflector_locations do
    local reflector_id = self.reflector_locations[i]
    self.reflector_data[reflector_id] = {}

    self.reflectors[reflector_id] = reflection.new()
    --[[ 0_0 ]]-- set looping on by default
    self.reflectors[reflector_id]:set_loop(1)                   
    self.reflectors[reflector_id].process = function(event)
      local value = event.value
      
      -- update the ui
      sun_mode_2.set_reflector_cursor(self, reflector_id, value)

      -- pass the event value to the router
      sun_mode_2.event_router(self, reflector_id, "process", value)

    end

    -- end-of-loop callback
    self.reflectors[reflector_id].end_of_loop_callback = function()
      sun_mode_2.event_router(self, reflector_id, "end_of_loop")
      -- print("reflector step", reflector_id)
    end
    
    -- (optional) callback for recording start
    self.reflectors[reflector_id].start_callback = function()
      sun_mode_2.event_router(self, reflector_id, "record_start")
      -- print("recording started", reflector_id)
    end
    
    -- (optional) callback for recording stop
    self.reflectors[reflector_id].end_of_rec_callback = function()
      sun_mode_2.event_router(self, reflector_id, "record_end")
      -- print("recording ended", reflector_id)
    end

    -- (optional) callback for reflector step
    self.reflectors[reflector_id].step_callback = function()
      sun_mode_2.event_router(self, reflector_id, "step")
      -- print("reflector step", reflector_id)
    end
    
    self.reflectors[reflector_id].end_callback = function()
      print("pattern end callback", reflector_id)
      sun_mode_2.event_router(self, reflector_id, "pattern_end")
      -- local is_looping = (self.loop[reflector_id] == 1)
      -- if not is_looping then self.play[reflector_id] = 0 end
    end
  end
end

------------------------------------------
-- sound making code
------------------------------------------

-- init lattice
function sun_mode_2.init_lattice(self)
  local sun = self.index
  
  self.lattice = lattice:new{
    auto = true,
    ppqn = 96
  }   

  -- make a sprockets for sun1 and sun 2
  self.sprocket_1 = self.lattice:new_sprocket{
    action = function(t) 
      sun_mode_2.event_router(self, nil, "sprocket")
    end,
    division = 1/4,
    enabled = true
  }
  
  self.sprocket_2 = self.lattice:new_sprocket{
    action = function(t) 
      sun_mode_2.event_router(self, nil, "sprocket")
    end,
    division = 1/8,
    enabled = true
  }

  self.lattice:start()
end

--======--===========================--======--
--======--111111111111111111111111111--======--
--===========  sun sound functions  =========--
--======--111111111111111111111111111--======--    
--======--===========================--======--

-- init lattice
function sun_mode_2.init_sounds(self)
  sun_mode_2.init_lattice(self)
end

-- define an event router that consolidates 
--   all the reflector events and lattice/sprocket events
function sun_mode_2.event_router(self, reflector_id, event_type, value)
  local sun = self.index
  
  if not self.sprocket_1 or not self.sprocket_2 then return end


  if sun == 1 then
    if event_type == "process" then 
      if reflector_id == 1 then 
        sun_mode_2.save_note(self,reflector_id,value)
      elseif reflector_id == 5 then
        sun_mode_2.set_cutoff(self,reflector_id,value)
      elseif reflector_id == 9 then
        sun_mode_2.set_attack(self,reflector_id,value)
      elseif reflector_id == 13 then
        sun_mode_2.set_release(self,reflector_id,value)
      end
    end
    if event_type == "sprocket"    then sun_mode_2.play_note(self) end
    
    -- unused events
    -- if event_type == "end_of_loop"  then --[[ do something with end_of_loop]] end
    -- if event_type == "record_start"  then --[[ do something with record_start]] end
    -- if event_type == "record_end"  then --[[ do something with record_end]] end
    -- if event_type == "step"      then --[[ do something with step]] end
    -- if event_type == "pattern_end"   then --[[ do something with pattern_end]] end
  elseif sun == 2 then
    -- print("sun 2",reflector_id,event_type,value)
    if event_type == "process" then 
      if reflector_id == 3 then 
        sun_mode_2.save_note(self,reflector_id,value)
      elseif reflector_id == 7 then
        sun_mode_2.set_cutoff(self,reflector_id,value)
      elseif reflector_id == 11 then
        sun_mode_2.set_attack(self,reflector_id,value)
      elseif reflector_id == 15 then
        sun_mode_2.set_release(self,reflector_id,value)
      end
    end

    if event_type == "sprocket" then sun_mode_2.play_note(self) end
    
    if event_type == "end_of_loop"  then 
      if reflector_id == 3 then
        local curr_div = suns[2].sprocket_2.division
        local next_div = curr_div == 1/8 and 1/16 or 1/8
        print("sun".. self.index .. ": end of loop 3 next division", next_div) 
        suns[2].sprocket_2.division = next_div
      else
        print("sun".. self.index .. ": end of loop 7 reset swing") 
        local curr_swing = suns[2].sprocket_2.swing 
        suns[2].sprocket_2:set_swing(curr_swing == 0 and 10 or 0)
      end
    end

    -- unused events
    -- if event_type == "record_start"  then --[[ do something with record_start]] end
    -- if event_type == "record_end"  then --[[ do something with record_end]] end
    -- if event_type == "step"      then --[[ do something with step]] end
    -- if event_type == "pattern_end"   then --[[ do something with pattern_end]] end
  end
end

-- local midi_notes = { 64, 66, 68, 69, 71, 73, 75 }
local hz_notes = { 329.62, 369.99, 415.30, 440.0, 493.88, 554.36, 622.25 }
local note_scalars = {0.5,1,2,4}

function sun_mode_2.save_note(self,reflector_id,value)
  local note_ix = math.floor(util.linlin(1,128,1,#hz_notes,value))
  local note = hz_notes[note_ix] * note_scalars[util.round(math.random()*3)+1]
  local note_num = musicutil.freq_to_note_num(note)  
  -- print("note",note_ix,value,note_num)
  self.note = note
end 

function sun_mode_2.play_note(self)
  if self.note then
    -- print("play note", self.note)
    engine.hz(self.note)
  end
end 


function sun_mode_2.set_cutoff(self,reflector_id,value)
  local cutoff = math.floor(util.linlin(1,128,100,10000,value))
  engine.cutoff(cutoff)
  -- print("set_cutoff",cutoff)
end 

function sun_mode_2.set_attack(self,reflector_id,value)
  local attack = util.linlin(1,128,0.001,0.25,value)
  engine.attack(attack)
  -- print("attack",attack)
end 

function sun_mode_2.set_release(self,reflector_id,value)
  local release = util.linlin(1,128,0.1,1,value)
  engine.release(release)
  -- print("release",release)
end 

function sun_mode_2.set_resonance(self,reflector_id,value)
  local resonance = util.linlin(1,128,0,3.5,value)
  engine.resonance(resonance)
  -- print("resonance",resonance)
end 

function sun_mode_2.set_amp(self,reflector_id,value)
  local amp = util.linlin(1,128,0,1,value)
  engine.amp(amp)
  -- print("amp",amp)
end 


return sun_mode_2

