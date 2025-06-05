-- kinesis (gestures): built for the habitus workshop
-- 0.1 @jaseknighter
-- l.llllllll.co/<insert link to lines thread>
--
--
-- Some notes about learning from this code:
--   Lines starting with "--" are comments, they don't get executed
--   Most comments help explain the code, but also:
--     Find the -- [[ 0_0 ]] -- for good places to change the code
--
-- This script has a UI build around the idea of two "suns" made up of "rays" and "photons"
--
-- Each sun operates in one of four "modes"
--   To change modes: press K1 + K2 (sun 1) or K1 + K3 (sun 2)
--
--   Mode 1
--     Sound behavior:  softcut
--     UI behavior:     Turning an encoder moves photons around the sun
--   Modes 2 
--     Sound behavior:  softcut
--     UI behavior:     The movement of photons in each ray gets recorded 
--                      and played back (using the reflection library)
--   Mode 3
--     Sound behavior:  Nothing by default. Up to you to define.
--     UI behavior:     Encoders activate a photon moving around its sun
--   Mode 4
--     Sound behavior:  Nothing by default. Up to you to define.
--     UI behavior:     Same as Mode 1

-- load norns modules
lattice = require("lattice")
reflection = require 'reflection'
musicutil = require 'musicutil'
fileselect=require 'fileselect'

engine.name = 'Sunshine'      -- use the Sunshine SuperCollider engine

include "lib/utilities"       -- load utilities written for this script
-- include "lib/tests/utilities_test"       -- load unit tests for lib/utilities

local Sun = include "lib/sun" 

screen_dirty = true

local num_sun_modes = 4
local prev_norns_menu_status = false
local redrawtimer
alt_key = false

suns = {}

-- There are 4 "modes" 
--   Note: modes 3 & 4 doesn't actually do anything sound-wise by default
--   Mode 1: (softcut controls) encoder sets photon velocity
--   Mode 2: (granular synth + reflection lib) each ray controls a different parameter
--   Mode 3: (generic) encoder changes the active "photon"
--   Mode 4: (generic) encoder sets photon velocity


-- By default, set sun 1 to mode 2 and sun 2 to mode 1
local current_modes = {2, 1} -- [[ 0_0 ]] -- change the default mode for each sun

-- All norns scripts call an init function when the script first loads
function init()
  screen.clear()
  init_sun(1)
  init_sun(2)

  -- Clear the softcut buffer in case it was being used by a previously loaded script
  softcut.buffer_clear()
 
  local redraw_rate = 1/15
  redrawtimer = metro.init(function()
    if prev_norns_menu_status and not norns.menu.status() then
      screen_dirty = true

    end
    prev_norns_menu_status = norns.menu.status()
    redraw()
  end, redraw_rate, -1)

  clock.run(function()
    clock.sleep(1) -- Delay starting the redraw timer to give the script time to finish initializing
    
    redrawtimer:start()
  end)
end

function init_sun(sun)
  local mode = current_modes[sun]
  if suns[sun] then suns[sun].deinit(suns[sun]) end
  suns[sun] = Sun:new(sun, mode)
  screen_dirty = true
end

function key(n, z)
  -- print("key", n, z) -- [[ 0_0 ]] --
  if n==1 then
    if  z==1 then
      alt_key = true
    elseif n==1 and z==0 then
      alt_key = false
    end
  elseif n==2 then
    if z==0 then
      if alt_key == true then
        current_modes[1] = util.wrap(current_modes[1]+1,1,num_sun_modes)
        init_sun(1,current_modes[1])
      end
    end
  elseif n==3 then 
    if z==0 then
      if alt_key == true then
        current_modes[2] = util.wrap(current_modes[2]+1,1,num_sun_modes)
        init_sun(2,current_modes[2])
      end
    end
  end

  if (n == 2 or n == 3) and alt_key == false then
    local sun_index = n - 1
    suns[sun_index]:key(n, z)
  end
end

function enc(n, delta)
  -- print("enc", n, delta) -- [[ 0_0 ]] --
  if n == 1 then
    suns[1]:enc(n,delta)
    suns[2]:enc(n,delta)
  elseif (n == 2 or n == 3) then
    local sun_index = n - 1
    suns[sun_index]:enc(n,delta)
  end
end

function redraw()
  if screen_dirty then 
    screen.clear()                        -- Clear the screen
    screen.level(3)                       -- Set a brightness level
    screen.move(2,5)                      -- 1st sun: move the screen cursor 
    screen.text("m"..current_modes[1])    -- 1st sun: draw the sun's number
    screen.move(67,5)                     -- 2nd sun: move the screen cursor 
    screen.text("m"..current_modes[2])    -- 2nd sun: draw the sun's number   
    screen.level(15)                      -- Set a brightness level for the screen
    screen.move(64,0)                     -- Move the drawing position the the top center
    screen.line(64,64)                    -- Draw a line to the bottom center
    screen.stroke()                       -- 
  end
  
  for i=1, 2 do
    suns[i]:redraw(screen_dirty)          -- Call each sun's redraw function
  end
  screen.update()                         -- Copy the screen buffer to the screen
  screen_dirty = false
  
end

