--  Based from the 0.14 Fronteer scenario: https://forums.factorio.com/viewtopic.php?f=36&t=33594
--  2018-3-8 MojoD
--  I did some dumb stuff to make it work for 0.16
--  added an infinite ocean to the left so the map cannot be cheezed like the old one scenario

-- 2020-05-02 Groumpfyy
--  - Added /movesilo command and /refreshsilo commands
--  - Made the silo moves work on chunks that have already been generated

local version = 2

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


-- Delete all silos, recreate 1 new one at the coordinate (preserve inventory)
local refresh_silo = function()
  seed_global_xy()

  -- Remove all silos blindly, we count the output inventory so we don't lose science
  local surface = game.get_surface(1)

  local input_inventory = {}
  local output_inventory = {}
  local rocket_inventory = {}
  local module_inventory = {}
  local rocket_parts = 0

  for _, entity in pairs(surface.find_entities_filtered{name = "rocket-silo"}) do
    local i = nil

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

    if entity.status == defines.entity_status.preparing_rocket_for_launch or
       entity.status == defines.entity_status.waiting_to_launch_rocket  or
       entity.status == defines.entity_status.launching_rocket then rocket_parts = 100 end -- so that we put the new silo in Preparing for launch

    if entity.rocket_parts then rocket_parts = rocket_parts + entity.rocket_parts end

    entity.destroy()
  end

  if rocket_parts > 100 then rocket_parts = 100 end -- Make sure we don't insert more than the max

  -- Clean the destination area so we can actually create the silo there, hope you didn't have anything there
  for _, entity in pairs(surface.find_entities_filtered{area = {{global.x+10, global.y+11},{global.x+18, global.y+19}}}) do
    entity.destroy()
  end

  -- Make sure we generate the chunk first (makes the game stutter a bit but I think it's fine)
  surface.request_to_generate_chunks({global.x+14, global.y+14}, 8)
  surface.force_generate_chunk_requests() 

  -- Create the silo first to create the chunk (otherwise tiles won't be settable)
  local silo = surface.create_entity{name = "rocket-silo", position = {global.x+14, global.y+14}, force = "player"}
  silo.destructible = false
  silo.minable = false

  -- Restore silo content and status (we re-create from scratch to avoid cheese and inconsistent states)
  for n,c in pairs(module_inventory) do
    silo.get_module_inventory().insert({name=n,count=c})
  end

  for n,c in pairs(output_inventory) do
    silo.get_output_inventory().insert({name=n,count=c})
  end

  for n,c in pairs(input_inventory) do
    silo.get_inventory(defines.inventory.assembling_machine_input).insert({name=n,count=c})
  end

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

local frontier = {}

-- script.on_event(defines.events.on_player_created, 
on_player_created = function(event)
  local player = game.players[event.player_index]
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
          local e = event.surface.create_entity{name = "stone-wall", position = {px, py}, force = "player"}
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
local on_player_changed_position = function(event)
  if not global.silo_created then
    global.silo_created = true
    refresh_silo()
  end

  local player = game.players[event.player_index]
  if player.position.x < (-left_water_boundary+24) then 
    player.print("Player was eaten by a Kraken!!!")
    player.character.die() 
  end
end

local register_commands = function()
  commands.add_command("refreshsilo", "Move the silo to match the current global.x/global.y settings", function(e) 
    refresh_silo(e)
    local player = game.players[e.player_index]
    player.print("Silo recreated")
  end)
  commands.add_command("movesilo", "Move the silo further/closer", function(e) 
    if not global.silo_created then
      global.silo_created = true
      refresh_silo()
    end
    offset = tonumber(e.parameter)
    if offset ~= nil then
      global.x = global.x + offset
      global.y = math.random(-silo_radius, silo_radius)
      refresh_silo(e)
      local player = game.players[e.player_index]
      player.print("Moved silo by " .. tostring(offset))
    end

  -- Control costs/internal values
  commands.add_command("addrocket", "Add (or remove) rockets to the win condition", function(e)
    rw = tonumber(e.parameter)
    if rw ~= nil then
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
      if global.move_cost_ratio < 1 then global.move_cost_ratio = 1 end
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

  commands.add_command("maxdistance", "Set the maximum distance for the silo, adding tiles past this will add launches", function(e)
    md = tonumber(e.parameter)
    if md ~= nil then
      global.max_distance = md
      if global.max_distance < 2*deathworld_boundary then global.max_distance = 2*deathworld_boundary end
    end
    game.print("The silo can now be at most "..tostring(global.max_distance).." tiles away.")
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

frontier.events =
{
  [defines.events.on_player_created] = on_player_created,
  [defines.events.on_chunk_generated] = on_chunk_generated,
  [defines.events.on_research_finished] = on_research_finished,
  [defines.events.on_player_changed_position] = on_player_changed_position,
  [defines.events.on_rocket_launched] = on_rocket_launched,
}

frontier.on_init = function()
  global.version = version
  global.silo_created = false

  -- Rockets/silo location management
  global.rockets_to_win = 1
  global.rockets_launched = 0
  
  global.move_cost_ratio = 1 -- If the multipler is 2, you need to buy 2x the tiles to actually move 1x
  global.move_step = 500 -- By default, we only move 500 tiles at a time
  
  global.rocket_step = 500 -- How many "tiles" past the max distance adds a launch

  global.max_distance = 100000 -- By default, 100k tiles max to the right
  
  global.move_buffer = 0 -- How many tiles we haven't currently reflected (between +move_step and -move_step)
  global.contributors = {} -- List of contributors so far (so that we can print when we actually move the silo)

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