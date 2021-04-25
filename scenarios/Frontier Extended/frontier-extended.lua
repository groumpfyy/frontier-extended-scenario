--  Based from the 0.14 Fronteer scenario: https://forums.factorio.com/viewtopic.php?f=36&t=33594
--  2018-3-8 MojoD
--  I did some dumb stuff to make it work for 0.16
--  added an infinite ocean to the left so the map cannot be cheezed like the old one scenario

-- 2020-05-02 Groumpfyy
--  - Added /movesilo command and /refreshsilo commands
--  - Made the silo moves work on chunks that have already been generated

-- 2021-04-14 Groumpfyy
-- - Moving the silo preserves contents/state
-- - Added commands to control internal state (cost per rocket/tile, max distance, number of rockets to win)

-- 2021-04-25 Groumpfyy
-- - Each death now adds one rocket to launch to win
-- - Added /autoratiostep <mult> <step> to multiply the cost of a tile by <mult> every <step>. Defaults to multiply by 2 every 50k tiles

local version = 3

local silo_center = 1700    --center point the silo will be to the right of spawn
local silo_radius = 450     --radius around center point the silo will be
local left_water_boundary = 250 --after this distance just generate water to a barrier
local deathworld_boundary = 350 --point where the ores start getting richer and biters begin

local ore_base_quantity   = 61  --base ore quantity, everything is scaled up from this
local ore_chunk_scale   = 32  --sets how fast the ore will increase from spawn, lower = faster

--passed the x distance from spawn and returns a number scaled up depending on how high it is
local ore_multiplier = function(distance)
  local a = math.max(1, math.abs(distance/ore_chunk_scale))
  a = math.min(a, 100)
  local multiplier = math.random(a, 4+a)
  return multiplier
end

local seed_global_xy = function()
  if global.x == nil or global.y == nil then
    -- math.random is fine for the jitter around x, but for y, we use the game tick... more random
    global.x = math.random(silo_center, (silo_center+silo_radius))
    global.y = game.tick%silo_radius - silo_radius/2 --  math.random(-silo_radius, silo_radius)
  end 
end

local signstr = function(amount)
  if amount > 0 then
    return "+"..tostring(amount)
  end
  return tostring(amount)
end

-- Delete all silos, recreate 1 new one at the coordinate (preserve inventory)
local refresh_silo = function(on_launch)
  seed_global_xy()

  -- Remove all silos blindly, we count the output inventory so we don't lose science
  local surface = game.get_surface(1)

  local output_inventory = {}
  local rocket_inventory = {}
  local module_inventory = {}
  local rocket_parts = 0

  for _, entity in pairs(surface.find_entities_filtered{name = "rocket-silo"}) do
    local i = nil
    local input_inventory = {} -- We do not keep the input inventory when it jumps, otherwise it looks like we managed to get something in it after it moved
    local has_inventory = false -- Because #input_inventory is broken in lua ?!

    -- What module the entity has
    i = entity.get_module_inventory()
    if i ~= nil then
      for n,c in pairs(i.get_contents()) do
        if module_inventory[n] == nil then module_inventory[n] = 0 end
        module_inventory[n] = module_inventory[n] + c
      end
    end

    -- What is in the input
    i = entity.get_inventory(defines.inventory.assembling_machine_input)
    if i ~= nil then
      for n,c in pairs(i.get_contents()) do
        if input_inventory[n] == nil then input_inventory[n] = 0 end
        input_inventory[n] = input_inventory[n] + c
        has_inventory = true
      end
    end

    -- What is in the output slot
    i = entity.get_output_inventory()
    if i ~= nil then
      for n,c in pairs(i.get_contents()) do
        if output_inventory[n] == nil then output_inventory[n] = 0 end
        output_inventory[n] = output_inventory[n] + c
      end
    end

    -- What is in the rocket (if there is one)
    i = entity.get_inventory(defines.inventory.rocket_silo_rocket)
    if i ~= nil then
      for n,c in pairs(i.get_contents()) do
        if rocket_inventory[n] == nil then rocket_inventory[n] = 0 end
        rocket_inventory[n] = rocket_inventory[n] + c
        if c > 0 then rocket_parts = 100 end -- There is something in a rocket, so it's ready to go
      end
    end

    -- When called from on_rocket_launch, the status is still launching_rocket, so we can't use this
    -- We must just ignore the status
    if not on_launch and (entity.status == defines.entity_status.preparing_rocket_for_launch or
       entity.status == defines.entity_status.waiting_to_launch_rocket  or
       entity.status == defines.entity_status.launching_rocket) then rocket_parts = 100 end -- so that we put the new silo in Preparing for launch

    if entity.rocket_parts~=nil and entity.rocket_parts>0 then rocket_parts = rocket_parts + entity.rocket_parts end

    local p = entity.position

    entity.destroy()

    -- We put a chest with the inputs so they are not lost
    if has_inventory then 
      chest = surface.create_entity{name = "wooden-chest", position = p, force="player", move_stuck_players=true}
      for n,c in pairs(input_inventory) do
        chest.insert({name=n,count=c})
      end
    end
  end

  if rocket_parts > 100 then rocket_parts = 100 end -- Make sure we don't insert more than the max

  -- Clean the destination area so we can actually create the silo there, hope you didn't have anything there
  for _, entity in pairs(surface.find_entities_filtered{area = {{global.x+10, global.y+11},{global.x+18, global.y+19}}}) do
    if entity.type ~= "character" then entity.destroy() end -- Don't go destroying players
  end

  -- Make sure we generate the chunk first (makes the game stutter a bit but I think it's fine)
  surface.request_to_generate_chunks({global.x+14, global.y+14}, 8)
  surface.force_generate_chunk_requests() 

  -- Remove enemy bases
  for _, entity in pairs(game.surfaces[1].find_entities_filtered{area = {{global.x+7, global.y+7},{global.x+21, global.y+21}}, force="enemy"}) do
    if entity.type ~= "character" then entity.destroy() end -- Don't go destroying (enemy) players
  end

  -- Create the silo first to create the chunk (otherwise tiles won't be settable)
  local silo = surface.create_entity{name = "rocket-silo", position = {global.x+14, global.y+14}, force = "player", move_stuck_players=true}
  silo.destructible = false
  silo.minable = false

  -- Restore silo content and status (we re-create from scratch to avoid cheese and inconsistent states)
  for n,c in pairs(module_inventory) do
    silo.get_module_inventory().insert({name=n,count=c})
  end

  for n,c in pairs(output_inventory) do
    silo.get_output_inventory().insert({name=n,count=c})
  end

  -- for n,c in pairs(input_inventory) do
  --   silo.get_inventory(defines.inventory.assembling_machine_input).insert({name=n,count=c})
  -- end

  for n,c in pairs(rocket_inventory) do
    silo.get_inventory(defines.inventory.rocket_silo_rocket).insert({name=n,count=c})
  end

  silo.rocket_parts = rocket_parts

  -- Put some concrete around it to be pretty (plus it leaves old concrete)
  local tiles = {}
  local i = 1
  for dx = -7,7 do
    for dy = -7,7 do
      tiles[i] = {name = "concrete", position = {global.x+dx+14, global.y+dy+14}}
      i=i+1
    end
  end
  surface.set_tiles(tiles, true)

  local tiles = {}
  local i = 1
  for df = -7,7 do
    tiles[i] = {name = "hazard-concrete-left", position = {global.x+df+14, global.y-7+14}}
    tiles[i+1] = {name = "hazard-concrete-left", position = {global.x+df+14, global.y+7+14}}
    tiles[i+2] = {name = "hazard-concrete-left", position = {global.x-7+14, global.y+df+14}}
    tiles[i+3] = {name = "hazard-concrete-left", position = {global.x+7+14, global.y+df+14}}
    i=i+4
  end
  surface.set_tiles(tiles, true)
end

local move_silo = function(amount, contributor, on_launch)
  seed_global_xy() -- We need to make sure that X/Y are seesed (in case someone moves the silo before moving)
  local surface = game.get_surface(1)

  -- Make sure that all the silos can be destroyed (we shouldn't have more than one, but just in case)
  local silo_empty = true
  if not on_launch then -- When we do not launch (external request)
    for _, entity in pairs(surface.find_entities_filtered{name = "rocket-silo"}) do
      local i1 = entity.get_inventory(defines.inventory.rocket_silo_rocket)
      local i2 = entity.get_inventory(defines.inventory.assembling_machine_input)
      if (i1 ~= nil and i1.get_item_count() > 0) or -- Are there inputs (we don't move once someone puts something in it)
         (i2 ~= nil and i2.get_item_count() > 0) or  -- Is there something in the rocket
         entity.status == defines.entity_status.preparing_rocket_for_launch or -- Is it in launch stage
         entity.status == defines.entity_status.waiting_to_launch_rocket  or
         entity.status == defines.entity_status.launching_rocket or
         (entity.rocket_parts or 0) > 0 then -- There are rocket parts made
        silo_empty = false
      end
    end
  end

  if global.x < global.max_distance then 
    local new_amount = math.floor((amount / global.move_cost_ratio)+0.5)
    if new_amount == 0 then -- We make sure that we don't move by zero (if the donation is too small and the ratio too large)
      if amount > 0 then new_amount = 1 end
      if amount < 0 then new_amount = -1 end
    end
    amount = new_amount
  end -- We do not use the ratio once we are in add-rocket territory
  global.move_buffer = global.move_buffer + amount

  -- Remember the caller
  if amount ~= 0 and contributor ~= "" and contributor ~= nil then 
    if amount > 0 then 
      table.insert(global.plus_contributors, contributor.."(+"..amount..")")
    else
     table.insert(global.minus_contributors, contributor.."("..amount..")")
   end
 end

  -- If it's enough to trigger a move and the silo is empty (or it was a launch in case we move "forcefully")
  local move_silo = ((math.abs(global.move_buffer) >= global.move_step or global.x + global.move_buffer >= global.max_distance) and silo_empty)
  if move_silo then
    local new_x = global.x
    if global.x + global.move_buffer >= global.max_distance then -- We reach the "end"
      global.move_buffer = global.x + global.move_buffer - global.max_distance
      new_x = global.max_distance
    else 
      if global.x + global.move_buffer < -left_water_boundary+30 then -- We are getting too close to water
        global.move_buffer = global.x + global.move_buffer - (-left_water_boundary+30)
        new_x = -left_water_boundary+30
      else -- We moved "enough"
        new_x = global.x + global.move_buffer
        global.move_buffer = 0
      end
    end

    if new_x ~= global.x then -- If there is actually a move (if we call refresh_silo without moving X, Y will randomely jump anyway)
      local str = ""
      if new_x > global.x then
        str = "Moved the silo forward by " .. tostring(new_x-global.x) .. " tiles thanks to the meanness of " .. table.concat(global.plus_contributors, ', ')
        if #global.minus_contributors > 0 then str = str.." and despite the kindness of "..table.concat(global.minus_contributors, ', ') end
      else
        str = "Moved the silo backward by " .. tostring(new_x-global.x) .. " tiles thanks to the kindness of " .. table.concat(global.minus_contributors, ', ')
        if #global.plus_contributors > 0 then str = str.." and despite the meanness of "..table.concat(global.plus_contributors, ', ') end
      end
      game.print(str)
      
      global.plus_contributors = {}
      global.minus_contributors = {}
      global.x = new_x
      global.y = math.random(-silo_radius, silo_radius)
      refresh_silo(on_launch) -- Effect the silo move

      if new_x >= global.max_distance then
        game.print("We have reached the MAXIMUM DISTANCE! Every "..tostring(global.rocket_step).." tiles will now add one more launch to win.")
        if global.move_buffer>0 then
          table.insert(global.plus_contributors, "everyone("..global.move_buffer..")")
          contributor = "everyone"
          amount = global.move_buffer
        end
      end
    else
      move_silo = false -- We didn't actually move the silo
    end
  end

  -- We reached the end, we now use the buffer to add rockets
  if global.x >= global.max_distance then
    local add_rocket = math.floor(global.move_buffer/global.rocket_step)
    if add_rocket > 0 then
      global.rockets_to_win = global.rockets_to_win + add_rocket
      global.move_buffer = global.move_buffer % global.rocket_step

      -- Build contributor lines
      local str_launch = tostring(add_rocket).." extra launches"
      if add_rocket == 1 then str_launch = "one extra launch" end

      local str = "Adding "..str_launch.." thanks to the meanness of " .. table.concat(global.plus_contributors, ', ')
      if #global.minus_contributors > 0 then str = str.." and despite the kindness of "..table.concat(global.minus_contributors, ', ') end
      game.print(str)

      global.plus_contributors = {}
      global.minus_contributors = {}
      
      str = tostring(global.rockets_to_win-global.rockets_launched).." launches to go!"
      if global.move_buffer > 0 then
        str = str.." And already "..tostring(global.move_buffer).." tiles out of "..tostring(global.rocket_step).." towards an extra launch."
      end
      game.print(str)
    else
      if amount > 0 then
        game.print("Thanks to "..contributor..", we are now "..tostring(global.move_buffer).." ("..signstr(amount)..") tiles out of "..tostring(global.rocket_step).." towards the next launch.")
      end
    end
  else -- We haven't reach the maximum distance, check if we should ack the contribution
    if amount ~= 0 and not move_silo then
      local str1 = "Thanks to "..contributor..", the silo will move by "..tostring(global.move_buffer).." ("..signstr(amount)..") tiles"
      if math.abs(global.move_buffer) < global.move_step then -- Below move threshold
        game.print(str1.." when we reach a total of "..tostring(global.move_step).." tiles.")
      else
        game.print(str1.." after the next launch.")
      end
    end
  end

  -- Keep track of the move forward for the purpose of multiplying cost
  if amount ~= 0 then 
    if global.x < global.max_distance then
      global.move_buffer_ratio = global.move_buffer_ratio + amount
      while global.move_buffer_ratio >= global.move_cost_step do
        global.move_cost_ratio = global.move_cost_ratio * global.move_cost_ratio_mult
        global.move_buffer_ratio = global.move_buffer_ratio - global.move_cost_step
        local next_increment = global.move_cost_step - global.move_buffer_ratio
        if next_increment < 0 then next_increment = 0 end
        game.print("You must now request "..tostring(global.move_cost_ratio).." tiles to actually move by one tile. In "..tostring(next_increment).." tiles, we'll multiply that cost by "..tostring(global.move_cost_ratio_mult).." again.")
      end
    else
      global.move_cost_ratio = global.move_cost_ratio_mult^math.floor(global.max_distance/global.move_cost_step)
      -- game.print("You must now request "..tostring(global.move_cost_ratio).." tiles to actually move by one tile. In "..tostring(next_increment).." tiles, we'll multiply that cost by "..tostring(global.move_cost_ratio_mult).." again.")
    end
  end
end  

local frontier = {}

-- script.on_event(defines.events.on_player_created, 
local on_player_created = function(event)
  if event.player_index == nil then return end
  local player = game.players[event.player_index]
  if player == nil then return end

  player.insert{name="iron-plate", count=8}
  player.insert{name="pistol", count=1}
  player.insert{name="firearm-magazine", count=10}
  player.insert{name="burner-mining-drill", count = 1}
  player.insert{name="stone-furnace", count = 1}
  player.insert{name="wood", count = 1}

  local chart_area = 200
  player.force.chart(player.surface, {{player.position.x - chart_area, player.position.y - chart_area}, {player.position.x + chart_area, player.position.y + chart_area}})

  if not global.skip_intro then
    if game.is_multiplayer() then
      player.print({"msg-intro"})
    else
      game.show_message_dialog{text = {"msg-intro"}}
    end
  end
end

-- When a new chunk is created, we make sure it's the right type based on the various region of the map (water, clear space, wall and the rest)
local on_chunk_generated = function(event)
  if event.surface.name ~= "nauvis" then return end
  
  --after going left far enough just generate water as a barrier to stop cheesing the map
  if event.area.left_top.x < -left_water_boundary then
    for _, entity in pairs(event.surface.find_entities_filtered{area = event.area}) do
      entity.destroy()
    end
    local tiles = {}
    local i = 1
    for dx = 0,31 do
      for dy = 0,31 do
        tiles[i] = {name = "deepwater", position = {event.area.left_top.x+dx, event.area.left_top.y+dy}}
        i=i+1
      end
    end
    event.surface.set_tiles(tiles, true)
  end
    
  --kill off biters inside the wall
  if event.area.right_bottom.x < (deathworld_boundary + 96) then
    for _, entity in pairs(event.surface.find_entities_filtered{area = event.area, force = "enemy"}) do
      entity.destroy()
    end
  end
  
  -- Wall chunk
  if event.area.left_top.x <= deathworld_boundary and event.area.right_bottom.x >= deathworld_boundary then
    for _, entity in pairs(event.surface.find_entities_filtered{area = event.area}) do
      entity.destroy()
    end
    for dy = 0, 31 do
      local py = event.area.left_top.y+dy
      for dx = 0, 4 do
        local px = event.area.left_top.x+dx+14
        if event.surface.can_place_entity{name = "stone-wall", position = {px, py}, force = "player"} then
          local e = event.surface.create_entity{name = "stone-wall", position = {px, py}, force = "player", move_stuck_players=true}
        end
      end
    end
  end
  
  --based off Frontier scenario, it scales freshly generated ore by a scale factor
  for _, resource in pairs(event.surface.find_entities_filtered{area = event.area, type="resource"}) do
    local a
    if resource.position.x > deathworld_boundary then a = ore_multiplier(resource.position.x-deathworld_boundary)
    else a = ore_multiplier(ore_base_quantity) end
    
    if resource.prototype.resource_category == "basic-fluid" then
      resource.amount = 3000 * 3 * a
    elseif resource.prototype.resource_category == "basic-solid" then
      resource.amount = ore_base_quantity * a
    end
  end 
end

-- Make sure rocket-silo research is never enabled
local on_research_finished = function(event)
  local recipes = event.research.force.recipes
  if recipes["rocket-silo"] then recipes["rocket-silo"].enabled = false end
end

-- Make sure we catch players going off-bound and ... KRAKEN
-- Also use the first time a player moves as our "randomness" for initial silo position
local on_player_died = function(event)
  if global.rockets_per_death <= 0 then return end

  local player_name = "a player"
  if event.player_index ~= nil then
    if game.players[event.player_index] ~= nil then
      player_name = game.players[event.player_index].name
    end
  end

  -- Build player death lines
  local add_rocket = global.rockets_per_death

  global.rockets_to_win = global.rockets_to_win + add_rocket
  if global.rockets_to_win < 1 then global.rockets_to_win = 1 end

  -- game.print("Rocket launches to win: " .. tostring(global.rockets_to_win).." with "..tostring(global.rockets_launched).." launches so far.")

  local str_launch = tostring(add_rocket).." extra launches"
  if add_rocket == 1 then str_launch = "one extra launch" end

  game.print("Adding "..str_launch.." thanks to the death of " .. player_name)
  game.print(tostring(global.rockets_to_win-global.rockets_launched).." launches to go!")
end

-- Make sure we catch players going off-bound and ... KRAKEN
-- Also use the first time a player moves as our "randomness" for initial silo position
local on_player_changed_position = function(event)
  if not global.silo_created then
    global.silo_created = true
    refresh_silo(false)
  end

  local player = game.players[event.player_index]
  if player.position.x < (-left_water_boundary+24) then 
    player.print("Player was eaten by a Kraken!!!")
    player.character.die() 
  end
end

local register_commands = function()
  commands.add_command("refreshsilo", "Move the silo to match the current global.x/global.y settings", function(e) 
    refresh_silo(false)
    if e.player_index ~= nil then
      if game.players[e.player_index] ~= nil then
        game.players[e.player_index].print("Silo recreated")
      end
    end
  end)
  commands.add_command("movesilo", "Move the silo further/closer (pass an amount and a contributor)", function(e) 
    local p = e.parameter
    if p == nil then p = "" end
    local parr = {}
    for str in string.gmatch(p, "([^%s]+)") do
      table.insert(parr, str)
    end
    if #parr < 2 then 
      if e.player_index ~= nil then
        if game.players[e.player_index] ~= nil then
          game.players[e.player_index].print("Not enough parameters to /movesilo")
        end
      end
      return
    end

    local amount = tonumber(table.remove(parr, 1))
    local user = table.remove(parr, 1)
    if amount ~= nil and user ~= nil then
      move_silo(amount, user, false)
    end
  end)

  -- Control costs/internal values
  commands.add_command("addrocket", "Add (or remove) rockets to the win condition", function(e)
    rw = tonumber(e.parameter)
    if rw ~= nil then
      global.scenario_finished = false
      if not global.rockets_to_win then
        global.rockets_to_win = rw
      else
        global.rockets_to_win = global.rockets_to_win + rw
      end
    end
    if global.rockets_to_win < 1 then global.rockets_to_win = 1 end

    game.print("Rocket launches to win: " .. tostring(global.rockets_to_win).." with "..tostring(global.rockets_launched).." launches so far.")
  end)

  commands.add_command("moveratio", "Set the ratio of move requested to actual move", function(e)
    cr = tonumber(e.parameter)
    if cr ~= nil then
      global.move_cost_ratio = cr
      if global.move_cost_ratio <= 0 then global.move_cost_ratio = 1 end
    end
    game.print("You need to request a "..tostring(global.move_cost_ratio).." tile move to actually move the silo 1 tile.")
  end)

  commands.add_command("rocketcost", "Set the cost in tiles for an additional launch", function(e)
    rs = tonumber(e.parameter)
    if rs ~= nil then
      global.rocket_step = rs
      if global.rocket_step < 1 then global.rocket_step = 1 end
    end
    game.print("Extra launches now cost "..tostring(global.rocket_step).." tiles each.")
  end)

  commands.add_command("rocketsperdeath", "Set the cost in rockets of a death", function(e)
    rs = tonumber(e.parameter)
    if rs ~= nil then
      global.rockets_per_death = rs
      if global.rockets_per_death < 0 then global.rockets_per_death = 0 end
    end
    game.print("Each player death now adds "..tostring(global.rockets_per_death).." rocket launches.")
  end)

  commands.add_command("maxdistance", "Set the maximum distance for the silo, adding tiles past this will add launches", function(e)
    md = tonumber(e.parameter)
    if md ~= nil then
      global.max_distance = md
      if global.max_distance < 2*deathworld_boundary then global.max_distance = 2*deathworld_boundary end
    end
    game.print("The silo can now be at most "..tostring(global.max_distance).." tiles away.")
  end)
  commands.add_command("autoratiostep", "Automatically multiply the cost ratio for on some step", function(e)
    local p = e.parameter
    if p == nil then p = "" end
    local parr = {}
    for str in string.gmatch(p, "([^%s]+)") do
      table.insert(parr, str)
    end
    if #parr < 2 then 
      if e.player_index ~= nil then
        if game.players[e.player_index] ~= nil then
          game.players[e.player_index].print("Not enough parameters to /autoratiostep, need <ratiomult> and <stepsize>")
        end
      end
      return
    end

    local ratiomult = tonumber(table.remove(parr, 1))
    local stepsize = tonumber(table.remove(parr, 1))

    if ratiomult ~= nil and stepsize ~= nil then
      global.move_cost_ratio_mult = ratiomult
      global.move_cost_step = stepsize
      game.print("The cost ratio will now be multiplied by "..tostring(global.move_cost_ratio_mult).." every "..tostring(global.move_cost_step).." tiles foward")
    end
  end)
  commands.add_command("movestep", "Set the number of actual tiles the silo moves in each step", function(e)
    ms = tonumber(e.parameter)
    if ms ~= nil then
      global.move_step = ms
      if global.move_step < 1 then global.move_step = 1 end
    end
    game.print("The silo will move in "..tostring(global.move_step).." tile increments.")
  end)
end

local on_rocket_launched = function(event)
  local rocket = event.rocket
  if not (rocket and rocket.valid) then return end

  local force = rocket.force  
  
  global.scenario_finished = global.scenario_finished or false
  if global.scenario_finished then
    return
  end

  global.rockets_launched = global.rockets_launched + 1

  if global.rockets_launched >= global.rockets_to_win then
    global.scenario_finished = true

    game.set_game_state
    {
      game_finished = true,
      player_won = true,
      can_continue = true,
      victorious_force = force
    }

    -- No more silo moves, we are done!
    return
  end

  game.print("Rocket launches so far: " .. tostring(global.rockets_launched)..", "..tostring(global.rockets_to_win-global.rockets_launched).." to go!.")

  -- A rocket was launched, we should check if there are deferred moves to do (and we do them no matter the inventory)
  move_silo(0,"",true)
end

frontier.events =
{
  [defines.events.on_player_created] = on_player_created,
  [defines.events.on_chunk_generated] = on_chunk_generated,
  [defines.events.on_research_finished] = on_research_finished,
  [defines.events.on_player_changed_position] = on_player_changed_position,
  [defines.events.on_player_died] = on_player_died,
  [defines.events.on_rocket_launched] = on_rocket_launched,
}

frontier.on_init = function()
  global.version = version
  global.silo_created = false

  -- Disable default victory and replace our own rocket launch screen (don't think it matters since we are replacing the silo-script entirely)
  global.no_victory = true

  -- Rockets/silo location management
  global.rockets_to_win = 1
  global.rockets_launched = 0
  global.scenario_finished = false
  
  global.move_cost_ratio = 1 -- If the multipler is 2, you need to buy 2x the tiles to actually move 1x
  global.move_step = 500 -- By default, we only move 500 tiles at a time
  
  global.rocket_step = 500 -- How many "tiles" past the max distance adds a launch

  global.rockets_per_death = 1 -- How many extra launch needed for each death

  global.max_distance = 100000 -- By default, 100k tiles max to the right
  
  global.move_cost_ratio_mult = 2 -- Be default, we increase the "cost" of a tile by 2
  global.move_cost_step = 50000 -- Every 50k tiles move
  global.move_buffer_ratio = 0 -- How many tiles we have moved since the last ratio multiplier

  global.move_buffer = 0 -- How many tiles we haven't currently reflected (between +move_step and -move_step)
  global.plus_contributors = {} -- List of contributors so far (so that we can print when we actually move the silo)
  global.minus_contributors = {} -- List of contributors so far (so that we can print when we actually move the silo)

  register_commands()
end

-- script.on_load(function()
frontier.on_load = function()
  register_commands()
end

frontier.on_configuration_changed = function(event)
  if global.version ~= version then
    global.version = version
    -- Overide map settings for biter expansion just to make sure poeple cant make it too easy
  game.map_settings.enemy_expansion.friendly_base_influence_radius = 0
  game.map_settings.enemy_expansion.min_expansion_cooldown = 1800 --30 seconds
  game.map_settings.enemy_expansion.max_expansion_cooldown = 14400  --4 minutes
  game.map_settings.enemy_expansion.max_expansion_distance = 5
  game.map_settings.enemy_evolution.destroy_factor = 0.0001
  --make pollution more willing to spread
  --game.map_settings.pollution.diffusion_ratio = .08  --not needed with 0.17
  end
end

return frontier