--  Based from the 0.14 Fronteer scenario: https://forums.factorio.com/viewtopic.php?f=36&t=33594
--  2018-3-8 MojoD
--  I did some dumb stuff to make it work for 0.16
--  added an infinite ocean to the left so the map cannot be cheezed like the old one scenario

-- 2020-05-02 Groumpyy
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

local refresh_silo = function()
  seed_global_xy()

  local surface = game.get_surface(1)
  for _, entity in pairs(surface.find_entities_filtered{name = "rocket-silo"}) do
    entity.destroy()
  end
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

  local tiles = {}
  local i = 1
  for dx = -7,7 do
    for dy = -7,7 do
      tiles[i] = {name = "concrete", position = {global.x+dx+14, global.y+dy+14}}
      i=i+1
    end
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
  end)
  commands.add_command("movesilo", "Move the silo further/closer", function(e) 
    offset = tonumber(e.parameter)
    if offset ~= nil then
      global.x = global.x + offset
      global.y = math.random(-silo_radius, silo_radius)
      refresh_silo(e)
    end
  end)
end

frontier.events =
{
  [defines.events.on_player_created] = on_player_created,
  [defines.events.on_chunk_generated] = on_chunk_generated,
  [defines.events.on_research_finished] = on_research_finished,
  [defines.events.on_player_changed_position] = on_player_changed_position,
}

frontier.on_init = function()
  global.version = version
  global.silo_created = false
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