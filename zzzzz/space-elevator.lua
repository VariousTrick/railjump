local SpaceElevator = {}
--[[
  storage.space_elevators = {
    unit_number = {
      type = "space-elevator",
      unit_number = entity.unit_number,
      valid = true,
      force_name = force_name,
      main = entity,
      surface = surface,
      zone = zone,
      opposite_struct = struct, --Struct on opposite zone.
      carriage_behind = LuaEntity, -- on the enter side
      carriage_ahead = LuaEntity, -- on the exit side
      position = position,
      direction = direction,
      collider = LuaEntity,
      station = LuaEntity,
      energy_interface = LuaEntity,
      energy_interface_output = LuaEntity,
      sub_entities = {LuaEntity}, -- rails and signals#
      watch_area = area -- calculated areas
      output_area = area

      -- the following are only on the primary (ground) structure
      power_switch = luaEntity
      built = false, -- wont' work until built.
      parts = 0, -- each craft counts as a part. parts is reduced by maintenance cost
      lua_energy = 0, -- the lua energy buffer
      total_energy = float -- cache for front end (gui + sticker text)
    }
  }
]]



SpaceElevator.on_train_teleport_started_event = script.generate_event_name()
SpaceElevator.on_train_teleport_finished_event = script.generate_event_name()


-- start at the higher end for now then reduce until competitive.
SpaceElevator.maintenance_min_multiplier = 0.25  -- 25%, 100% for a max gravity planet
SpaceElevator.maintenance_per_stack_up = 0.005   -- at max gravity.
SpaceElevator.maintenance_per_stack_down = 0.001 -- at max gravity.
SpaceElevator.maintenance_per_second = 0.1
-- these are way too low for now
SpaceElevator.energy_per_stack_up = -2000000
SpaceElevator.energy_per_stack_down = 1000000                           -- recharge the battery
SpaceElevator.energy_buffer = 10000000000
SpaceElevator.interface_energy_buffer = SpaceElevator.energy_buffer / 2 -- for the entity
SpaceElevator.energy_passive_draw = SpaceElevator.energy_buffer / 1000  --10MJ
SpaceElevator.energy_min = .25 * SpaceElevator.energy_buffer

SpaceElevator.parts_per_radius = 0.2 -- 8.3 minutes for max radius
SpaceElevator.parts_display_threshold = 0.98

SpaceElevator.passive_train_speed = 0.1
SpaceElevator.max_train_speed = 0.5
SpaceElevator.player_teleport_distance = 15

SpaceElevator.teleport_next_tick_frequency = 4

local east = defines.direction.east
local west = defines.direction.west

SpaceElevator.stock_types = { "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" }
SpaceElevator.name_space_elevator = mod_prefix .. "space-elevator"
SpaceElevator.name_energy_interface = mod_prefix .. "space-elevator-energy-interface"
SpaceElevator.name_space_elevator_overlay_left = mod_prefix .. "space-elevator-left"
SpaceElevator.name_space_elevator_overlay_right = mod_prefix .. "space-elevator-right"
SpaceElevator.name_space_elevator_train_collider = mod_prefix .. "space-elevator-train-collider"
SpaceElevator.name_train_collision_detector = mod_prefix .. "train-collision-detection"

SpaceElevator.name_sound_train_start = mod_prefix .. "sound-elevator-carriage-up" -- new train
SpaceElevator.name_sound_train_end = mod_prefix .. "sound-elevator-carriage-up"   -- end of train

SpaceElevator.name_sound_carriage_up = mod_prefix .. "sound-elevator-carriage-up"
SpaceElevator.name_sound_carriage_down = mod_prefix .. "sound-elevator-carriage-down"
SpaceElevator.name_sound_train_up = mod_prefix .. "sound-elevator-train-up"
SpaceElevator.name_sound_train_down = mod_prefix .. "sound-elevator-train-down"
SpaceElevator.name_sound_train_start = mod_prefix .. "sound-elevator-train-start"
SpaceElevator.name_sound_train_stop = mod_prefix .. "sound-elevator-train-stop"


SpaceElevator.name_tug = mod_prefix .. "space-elevator-tug"
SpaceElevator.name_part = mod_prefix .. "space-elevator-cable"
SpaceElevator.space_elevator_radius = 12
SpaceElevator.space_elevator_hypertrain_radius = 12
SpaceElevator.space_elevator_watch_rect = {
  [east] = { left_top = { x = -11, y = -11 }, right_bottom = { x = 0, y = 0 } },
  [west] = { left_top = { x = 0, y = -11 }, right_bottom = { x = 11, y = 0 } },
}
SpaceElevator.space_elevator_force_forward_rect = { left_top = { x = -11, y = -11 }, right_bottom = { x = 11, y = 11 } }
SpaceElevator.space_elevator_width = 24
SpaceElevator.space_elevator_collider_position = {
  [east] = { x = -3, y = -3.5 },
  [west] = { x = 3, y = -3.5 }
}
SpaceElevator.space_elevator_output = {
  [east] = { x = 5, y = -2 },
  [west] = { x = -5, y = -2 },
}
--[[SpaceElevator.space_elevator_output_tug = {
  [east] = {x=5, y=-2},
  [west] = {x=-5, y=-2},
}]]
SpaceElevator.space_elevator_output_tug = {
  [east] = { x = 1, y = -6 },
  [west] = { x = -1, y = -6 },
}
SpaceElevator.space_elevator_output_rect = {
  [east] = { left_top = { x = 0, y = -12 }, right_bottom = { x = 12, y = 12 } },
  [west] = { left_top = { x = -12, y = -12 }, right_bottom = { x = 0, y = 12 } },
}

SpaceElevator.internals = {
  shared = {
    ["se-space-elevator-blocker-vertical"] = {
      { position = { x = -10.85, y = -4.85 }, direction = defines.direction.north },
      { position = { x = -10.85, y = 7.85 },  direction = defines.direction.north },
      { position = { x = -10.85, y = -2 },    direction = defines.direction.north },
      { position = { x = 10.85, y = 7.85 },   direction = defines.direction.north },
      { position = { x = 10.85, y = -4.85 },  direction = defines.direction.north },
      { position = { x = 10.85, y = -2 },     direction = defines.direction.north },
    },
    ["se-space-elevator-blocker-horizontal"] = {
      { position = { x = 0, y = 10.85 },     direction = defines.direction.east },
      { position = { x = -7.85, y = 10.85 }, direction = defines.direction.east },
      { position = { x = 7.85, y = 10.85 },  direction = defines.direction.east },
      { position = { x = 0, y = -7.85 },     direction = defines.direction.east },
      { position = { x = -7.85, y = -7.85 }, direction = defines.direction.east },
      { position = { x = 7.85, y = -7.85 },  direction = defines.direction.east },
    },
    ["se-space-elevator-legacy-straight-rail"] = {
      { position = { x = -5.5, y = -1.5 }, direction = defines.direction.southeast },
      { position = { x = 4.5, y = -1.5 },  direction = defines.direction.southwest },
    },
    ["se-space-elevator-legacy-curved-rail"] = {
      { position = { x = 2, y = -4 },  direction = defines.direction.south },
      { position = { x = -2, y = -4 }, direction = defines.direction.southwest },
      { position = { x = 8, y = 2 },   direction = defines.direction.northwest },
      { position = { x = -8, y = 2 },  direction = defines.direction.east },
    },
    ["se-space-elevator-lamp"] = {
      { position = { x = 0, y = 0 }, direction = defines.direction.north },
    },
    ["se-space-elevator-energy-interface"] = {
      { position = { x = 0, y = 0 }, direction = defines.direction.north },
    },
    ["se-space-elevator-energy-pole"] = {
      { position = { x = 0, y = 0 }, direction = defines.direction.north },
    },
    ["se-space-elevator-power-switch"] = {
      { position = { x = 0, y = 0 }, direction = defines.direction.north, primary_only = true },
    },
  },
  [east] = {
    ["se-space-elevator-legacy-straight-rail"] = {
      { position = { x = -1, y = -9 }, direction = defines.direction.north },
    },
    ["se-space-elevator-rail-signal"] = {
      { position = { x = -11.5, y = 4.5 }, direction = defines.direction.west },
      { position = { x = 11.5, y = 4.5 },  direction = defines.direction.west },
    },
    ["se-space-elevator-train-stop"] = {
      { position = { x = 1, y = -9 }, direction = defines.direction.north },
    },
  },
  [west] = {
    ["se-space-elevator-legacy-straight-rail"] = {
      { position = { x = 1, y = -9 }, direction = defines.direction.north },
    },
    ["se-space-elevator-rail-signal"] = {
      { position = { x = -11.5, y = 1.5 }, direction = defines.direction.east },
      { position = { x = 11.5, y = 1.5 },  direction = defines.direction.east },
    },
    ["se-space-elevator-train-stop"] = {
      { position = { x = 3, y = -9 }, direction = defines.direction.north },
    },
  }
}

---@param entity LuaEntity
---@return SpaceElevatorInfo?
function SpaceElevator.from_entity(entity)
  return SpaceElevator.from_unit_number(entity.unit_number)
end

---@param unit_number uint
---@return SpaceElevatorInfo?
function SpaceElevator.from_unit_number(unit_number)
  return storage.space_elevators[unit_number]
end

-- draw the part the sits over the train.
---@param struct SpaceElevatorInfo
function SpaceElevator.draw_top(struct)
  rendering.draw_sprite {
    surface = struct.surface,
    sprite = struct.direction == east and SpaceElevator.name_space_elevator_overlay_right or SpaceElevator.name_space_elevator_overlay_left,
    render_layer = 132,
    target = struct.main,
  }
end

---@param struct SpaceElevatorInfo
function SpaceElevator.setup_struct(struct)
  local primary = SpaceElevator.struct_primary(struct)
  local sub_entities = {}
  for _, entity_set in pairs({ SpaceElevator.internals.shared, SpaceElevator.internals[struct.direction] }) do
    for proto_name, placements in pairs(entity_set) do
      for _, placement in pairs(placements) do
        if struct.is_primary or not placement.primary_only then
          local sub_entity = struct.surface.create_entity {
            name = proto_name,
            position = Util.vectors_add(struct.position, placement.position),
            direction = placement.direction,
            force = struct.force_name
          }
          ---@cast sub_entity -?
          if not sub_entity then
            game.print("Error placing " .. proto_name)
            return
          end
          sub_entity.destructible = false
          if sub_entity.type == "train-stop" then
            if struct.parts == nil then
              sub_entity.backer_name = "[img=entity/" .. SpaceElevator.name_space_elevator ..
                  "]  " .. primary.name .. " ↓"
            else
              sub_entity.backer_name = "[img=entity/" .. SpaceElevator.name_space_elevator ..
                  "]  " .. primary.name .. " ↑"
            end
            struct.station = sub_entity
          elseif sub_entity.type == "electric-energy-interface" then
            if sub_entity.name == SpaceElevator.name_energy_interface then
              struct.energy_interface = sub_entity
            end
            sub_entity.power_usage = 0
            sub_entity.energy = 0
            sub_entity.electric_buffer_size = SpaceElevator.interface_energy_buffer
          elseif sub_entity.type == "electric-pole" then
            struct.electric_pole = sub_entity
          elseif sub_entity.type == "power-switch" then
            sub_entity.power_switch_state = true
            struct.power_switch = sub_entity
          else
            table.insert(sub_entities, sub_entity)
          end
        end
      end
    end
  end
  struct.sub_entities = sub_entities

  struct.collider = struct.surface.create_entity {
    name = SpaceElevator.name_space_elevator_train_collider,
    position = Util.vectors_add(struct.position, SpaceElevator.space_elevator_collider_position[struct.direction]),
    force = "neutral"
  }

  storage.space_elevators[struct.unit_number] = struct

  -- move character out of the way.
  local characters = struct.surface.find_entities_filtered { type = "character", area = util.position_to_area(struct.position, SpaceElevator.space_elevator_radius) }
  for _, character in pairs(characters) do
    teleport_non_colliding(character, character.position, 12, 0.5)
  end
end

---@param struct SpaceElevatorInfo
---@param new_name string
function SpaceElevator.rename(struct, new_name)
  local primary = SpaceElevator.struct_primary(struct)
  primary.name = new_name
  local station_name_base = "[img=entity/" .. SpaceElevator.name_space_elevator .. "]  " .. primary.name
  primary.station.backer_name = station_name_base .. " ↑"
  primary.opposite_struct.station.backer_name = station_name_base .. " ↓"
  -- TODO: update open UIs
end

---@param event EntityCreationEvent Event data
function SpaceElevator.on_entity_created(event)
  local entity = util.get_entity_from_event(event)
  if not entity then return end

  if not (entity.name == SpaceElevator.name_space_elevator or (entity.type == "entity-ghost" and entity.ghost_name == SpaceElevator.name_space_elevator)) then
    return
  end

  local player_index = event.player_index
  local is_ghost = entity.type == "entity-ghost"
  local surface = entity.surface
  local force = entity.force
  local force_name = entity.force.name
  local zone = Zone.from_surface(entity.surface)

  if cancel_creation_when_invalid(zone, entity, event) then return end
  ---@cast zone -?

  if not RemoteView.is_intersurface_unlocked_force(force_name) then
    cancel_entity_creation(entity, player_index,
      RemoteView.intersurface_unlock_requirement_string_2(force_name,
        "space-exploration.space-elevator-requires-satellite"), event)
    return
  end

  local opposite_zone
  if Zone.is_solid(zone) then
    ---@cast zone PlanetType|MoonType
    opposite_zone = zone.orbit
  elseif zone.type == "orbit" and Zone.is_solid(zone.parent) then
    ---@cast zone OrbitType
    opposite_zone = zone.parent
  else
    ---@cast zone -PlanetType, -MoonType
    cancel_entity_creation(entity, player_index, { "space-exploration.space-elevator-placement-invalid-zone" }, event)
    return
  end
  local opposite_surface = Zone.get_make_surface(opposite_zone)
  if not opposite_surface then
    cancel_entity_creation(entity, player_index, "The opposite surface (planet vs orbit) could not be found.", event)
    return
  end

  local direction -- direction of travel, 2-way rotation
  local position = entity.position
  if entity.direction == defines.direction.east or entity.direction == defines.direction.south then
    direction = defines.direction.east
  else
    direction = defines.direction.west
  end

  opposite_surface.request_to_generate_chunks(position, 2)
  opposite_surface.force_generate_chunk_requests()

  if is_ghost then
    if not opposite_surface.can_place_entity {
          name = SpaceElevator.name_space_elevator,
          position = position,
          direction = direction,
          force = entity.force
        } then
      if player_index then
        game.get_player(player_index).print({
          "space-exploration.space-elevator-placement-invalid-opposite-alert",
          --util.gps_tag(surface.name, position),
          util.gps_tag(opposite_surface.name, position)
        })
        rendering.draw_rectangle {
          surface = surface,
          filled = false,
          width = 8,
          color = { r = 0.1, g = 0.1, b = 0, a = 0.01 },
          left_top = util.vectors_add(position, { x = -SpaceElevator.space_elevator_radius, y = -SpaceElevator.space_elevator_radius }),
          right_bottom = util.vectors_add(position, { x = SpaceElevator.space_elevator_radius, y = SpaceElevator.space_elevator_radius }),
          time_to_live = 10 * 60,
          forces = { force }
        }
        rendering.draw_rectangle {
          surface = opposite_surface,
          filled = false,
          width = 8,
          color = { r = 0.1, g = 0.1, b = 0, a = 0.01 },
          left_top = util.vectors_add(position, { x = -SpaceElevator.space_elevator_radius, y = -SpaceElevator.space_elevator_radius }),
          right_bottom = util.vectors_add(position, { x = SpaceElevator.space_elevator_radius, y = SpaceElevator.space_elevator_radius }),
          time_to_live = 10 * 60,
          forces = { force }
        }
      end
      cancel_entity_creation(entity, player_index, { "space-exploration.space-elevator-placement-invalid-opposite" },
        event)
    end

    return
  end

  -- real version only beyond this point

  if direction ~= entity.direction then
    local old_entity = entity
    entity = surface.create_entity {
      name = SpaceElevator.name_space_elevator,
      position = old_entity.position,
      direction = direction,
      force = old_entity.force
    }
    ---@cast entity -?
    old_entity.destroy()
  end

  if not opposite_surface.can_place_entity {
        name = SpaceElevator.name_space_elevator,
        position = position,
        direction = direction,
        force = entity.force
      } then
    if player_index then
      game.get_player(player_index).print({
        "space-exploration.space-elevator-placement-invalid-opposite-alert",
        --util.gps_tag(surface.name, position),
        util.gps_tag(opposite_surface.name, position)
      })
      rendering.draw_rectangle {
        surface = surface,
        filled = false,
        width = 8,
        color = { r = 0.1, g = 0.1, b = 0, a = 0.01 },
        left_top = util.vectors_add(position, { x = -SpaceElevator.space_elevator_radius, y = -SpaceElevator.space_elevator_radius }),
        right_bottom = util.vectors_add(position, { x = SpaceElevator.space_elevator_radius, y = SpaceElevator.space_elevator_radius }),
        time_to_live = 10 * 60,
        forces = { force }
      }
      rendering.draw_rectangle {
        surface = opposite_surface,
        filled = false,
        width = 8,
        color = { r = 0.1, g = 0.1, b = 0, a = 0.01 },
        left_top = util.vectors_add(position, { x = -SpaceElevator.space_elevator_radius, y = -SpaceElevator.space_elevator_radius }),
        right_bottom = util.vectors_add(position, { x = SpaceElevator.space_elevator_radius, y = SpaceElevator.space_elevator_radius }),
        time_to_live = 10 * 60,
        forces = { force }
      }
    end
    cancel_entity_creation(entity, player_index, { "space-exploration.space-elevator-placement-invalid-opposite" }, event)
    return
  end

  -- test that the space is clear and buildable.
  local opposite_entity = opposite_surface.create_entity {
    name = SpaceElevator.name_space_elevator,
    position = entity.position,
    direction = direction,
    force = entity.force
  }
  ---@cast opposite_entity -?

  local watch_area = Util.area_add_position(SpaceElevator.space_elevator_watch_rect[direction], position)
  local output_area = Util.area_add_position(SpaceElevator.space_elevator_output_rect[direction], position)

  local struct = {
    type = "space-elevator",
    unit_number = entity.unit_number,
    surface = surface,
    position = position,
    valid = true,
    last_crafts = 0,
    force_name = force_name,
    main = entity,
    direction = direction,
    zone = zone,
    opposite_struct = nil,
    watch_area = watch_area,
    output_area = output_area,
  }
  local opposite_struct = {
    type = "space-elevator",
    unit_number = opposite_entity.unit_number,
    surface = opposite_surface,
    position = position,
    valid = true,
    last_crafts = 0,
    force_name = force_name,
    main = opposite_entity,
    direction = direction,
    zone = opposite_zone,
    opposite_struct = struct,
    watch_area = watch_area,
    output_area = output_area,
  }
  struct.opposite_struct = opposite_struct
  local primary = Zone.is_solid(zone) and struct or opposite_struct
  primary.is_primary = true
  primary.opposite_struct.is_primary = false
  primary.parts = 0
  --primary.parts = SpaceElevator.parts_per_radius * SpaceElevator.struct_radius(struct) + 1
  primary.built = false
  primary.name = primary.zone.name
  primary.total_energy = 0 -- cached for reading
  primary.lua_energy = 0   -- the lua energy buffer
  --struct.parts_to_finish = primary.zone.radius * SpaceElevator.parts_per_radius

  SpaceElevator.setup_struct(struct)
  SpaceElevator.setup_struct(opposite_struct)

  SpaceElevator.draw_top(struct)
  SpaceElevator.draw_top(opposite_struct)
end

Event.addListener(defines.events.on_built_entity, SpaceElevator.on_entity_created)
Event.addListener(defines.events.on_robot_built_entity, SpaceElevator.on_entity_created)
Event.addListener(defines.events.script_raised_built, SpaceElevator.on_entity_created)
Event.addListener(defines.events.script_raised_revive, SpaceElevator.on_entity_created)


---@param event EventData.on_trigger_created_entity Event data
function SpaceElevator.on_trigger_created_entity(event)
  if not event.entity and event.entity.valid then return end
  if event.entity.name == SpaceElevator.name_train_collision_detector then
    -- train has hit a train collider.
    SpaceElevator.check_carriage_at_location(event.entity.surface, event.entity.position)
  end
end

Event.addListener(defines.events.on_trigger_created_entity, SpaceElevator.on_trigger_created_entity)

---@param struct SpaceElevatorInfo
---@return number
function SpaceElevator.struct_radius(struct)
  return SpaceElevator.struct_primary(struct).zone.radius
end

---@param struct SpaceElevatorInfo
---@return SpaceElevatorInfo
function SpaceElevator.struct_primary(struct)
  return struct.is_primary and struct or struct.opposite_struct
end

---@param entity_name string
---@return integer
function SpaceElevator.get_inventory_size(entity_name)
  local prototype = prototypes.entity[entity_name]
  if prototype.type == "cargo-wagon" then
    return 5 + (prototype.get_inventory_size(defines.inventory.cargo_wagon) or 0)
  elseif prototype.type == "fluid-wagon" then
    return 5 + prototype.fluid_capacity / 650
  elseif prototype.type == "artillery-wagon" then
    return 10 + (prototype.get_inventory_size(defines.inventory.artillery_turret_ammo) or 0)
        + (prototype.get_inventory_size(defines.inventory.artillery_turret_ammo) or 0)
  else
    return 5 + (prototype.get_inventory_size(defines.inventory.fuel) or 0)
  end
end

---@param surface LuaSurface
---@param position MapPosition
function SpaceElevator.check_carriage_at_location(surface, position)
  for _, struct in pairs(storage.space_elevators) do
    if not (struct.main and struct.main.valid and struct.opposite_struct.main and struct.opposite_struct.main.valid) then
      SpaceElevator.space_elevator_destroy(struct)
      return
    end

    if (struct.carriage_behind == nil or not struct.carriage_behind.valid) and
        struct.surface == surface and
        Util.position_in_rect(struct.main.bounding_box, position) then
      --[[ debug watch
      rendering.draw_rectangle{
        surface = surface,
        left_top = watch_rect.left_top,
        right_bottom = watch_rect.right_bottom,
        color = {0,0,0.5, 0.5},
        time_to_live = 60,
        filled = true
      }]]

      -- find the carriage
      local carriages = surface.find_entities_filtered { type = SpaceElevator.stock_types, area = struct.watch_area, limit = 1 }
      if next(carriages) then
        struct.carriage_behind = carriages[1]
        struct.carriage_ahead = nil
        return
      end
    end
  end
end

---@param struct SpaceElevatorInfo
function SpaceElevator.finish_teleport(struct)
  if struct.carriage_ahead then --might be first carriage couldn't cross and is no longer there
    struct.surface.create_entity {
      name = SpaceElevator.name_sound_train_stop,
      position = struct.position
    }
    struct.opposite_struct.surface.create_entity {
      name = SpaceElevator.name_sound_train_stop,
      position = struct.opposite_struct.position
    }

    if struct.tug and struct.tug.valid then -- destroying part of the train resets the current scheduled stop
      local current = struct.carriage_ahead.train.schedule and struct.carriage_ahead.train.schedule.current
      struct.tug.destroy()
      if current then struct.carriage_ahead.train.get_schedule().go_to_station(current) end
    end
    struct.tug = nil
  end

  local carriage_ahead = struct.carriage_ahead
  struct.carriage_behind = nil
  struct.carriage_ahead = nil

  -- Raise on_train_teleport_finished event after the last carriage is created on the new surface and the elevator is reset.
  if carriage_ahead then
    script.raise_event(SpaceElevator.on_train_teleport_finished_event,
      {
        train = carriage_ahead.train,
        old_train_id_1 = struct.old_train_id,
        old_surface_index = struct.surface.index,
        teleporter = struct.entity
      })
  end
end

---@param struct SpaceElevatorInfo
---@param carriage LuaEntity
function SpaceElevator.create_tug(struct, carriage)
  -- place a "tug" behind the carriage
  struct.tug = struct.opposite_struct.surface.create_entity {
    name = SpaceElevator.name_tug,
    position = Util.vectors_add(SpaceElevator.space_elevator_output_tug[struct.direction], struct.position),
    direction = struct.direction,
    force = carriage.force,
    color = carriage.color
  }
  if not struct.tug then
    Log.debug("No tug created")
  else
    struct.tug.backer_name = ""
    struct.tug.destructible = false
  end
end

---@param struct SpaceElevatorInfo
---@param primary SpaceElevatorInfo Primarytruct of this space elevator (passed along for performance reasons)
---@param tick uint Current tick
---@param offset_tick uint current tick offset by elevator unit number
function SpaceElevator.space_elevator_teleport_next(struct, primary, tick, offset_tick)
  if (not struct.carriage_behind) or (not struct.carriage_behind.valid) or struct.carriage_behind.surface ~= struct.surface then
    struct.carriage_behind = nil
    struct.carriage_ahead = nil

    if offset_tick % (SpaceElevator.teleport_next_tick_frequency * 15) == 0 then
      --[[rendering.draw_rectangle{
        surface = struct.surface,
        left_top = watch_rect.left_top,
        right_bottom = watch_rect.right_bottom,
        color = {0,0,0.5, 0.5},
        time_to_live = 60,
        filled = true
      }]]
      --check if there was another train waiting
      local carriages = struct.surface.find_entities_filtered {
        type = SpaceElevator.stock_types,
        area = struct.watch_area,
        limit = 1
      }
      if carriages[1] then
        struct.carriage_behind = carriages[1]
      end
    end
    if not struct.carriage_behind then
      return
    end
  end

  local carriage
  if struct.carriage_behind and struct.carriage_behind.valid then carriage = struct.carriage_behind end
  ---@cast carriage -?
  local carriage_ahead
  if struct.carriage_ahead and struct.carriage_ahead.valid then carriage_ahead = struct.carriage_ahead end
  -- try to move the carriage to the other end's output
  -- for now just use the own elevator's output.
  local can_place_new_carriage = struct.opposite_struct.surface.can_place_entity {
    name = carriage.name,
    position = Util.vectors_add(SpaceElevator.space_elevator_output[struct.direction], struct.position),
    direction = defines.direction.south,
    force = carriage.force
  }
  local output_clear = struct.opposite_struct.surface.count_entities_filtered {
    type = SpaceElevator.stock_types,
    area = struct.output_area,
    limit = 1
  } == 0
  --[[ -- debug output
  rendering.draw_rectangle{
    surface = struct.opposite_struct.surface,
    left_top = output_area.left_top,
    right_bottom = output_area.right_bottom,
    color = {0.5,0,0, 0.5},
    time_to_live = 5,
    filled = true
  }]]

  -- Check for banned items, only for a new train
  local has_banned_items = false
  if next(storage.items_banned_from_transport) and not carriage_ahead then
    local banned_items = {}
    for _, carriage_to_check in pairs(carriage.train.carriages) do
      if carriage_to_check.type == "cargo-wagon" then
        local banned_items_in_wagon = find_items_banned_from_transport(carriage_to_check.get_inventory(defines.inventory
          .cargo_wagon))
        util.concatenate_tables(banned_items, banned_items_in_wagon)
      end
    end
    if next(banned_items) then
      has_banned_items = true
      local gps_tag = util.gps_tag(carriage.surface.name, carriage.position)
      if offset_tick % (SpaceElevator.teleport_next_tick_frequency * 80) == 0 then
        carriage.force.print({ "space-exploration.banned-items-in-train", gps_tag, serpent.line(banned_items) })
      end
    end
  end

  if can_place_new_carriage and (carriage_ahead or output_clear) and not has_banned_items then
    local carriage_behind = carriage.get_connected_rolling_stock(defines.rail_direction.front) or
        carriage.get_connected_rolling_stock(defines.rail_direction.back)

    -- Save manual mode and schedule info for restoring later
    local carriage_ahead_manual_mode
    local carriage_ahead_current_stop
    if carriage_ahead then
      local carriage_ahead_train = struct.carriage_ahead.train --[[@as LuaTrain]]
      carriage_ahead_manual_mode = carriage_ahead_train.manual_mode
      if carriage_ahead_train.schedule then
        carriage_ahead_current_stop = carriage_ahead_train.schedule.current
      end
    else -- New train
      carriage_ahead_manual_mode = carriage.train.manual_mode
    end

    -- IMPORTANT: crating a carriage tries to auto-connect rolling stock, and if it does it will destroy the existing trains
    -- It may also connect to unwanted trains
    -- TODO: detect if it was connected to a train, find out what the settings of the other train were before, and fix the other train.
    -- enter E = 0.85ish -- 0.37ish backwards
    -- enter W = 0.13ish -- 0.62ish backwards
    local spawn_direction
    if struct.direction == east then
      spawn_direction = carriage.orientation > 0.5 and defines.direction.south or defines.direction.north
    else
      spawn_direction = carriage.orientation > 0.5 and defines.direction.south or defines.direction.north
    end
    local new_carriage
    if struct.tug and struct.tug.valid then
      struct.tug.destroy()
      struct.tug = nil
    end

    if not carriage_ahead then
      -- place a "tug" behind where the carriage will be
      SpaceElevator.create_tug(struct, carriage)

      struct.surface.create_entity {
        name = SpaceElevator.name_sound_train_up,
        position = struct.position
      }
      struct.opposite_struct.surface.create_entity {
        name = SpaceElevator.name_sound_train_down,
        position = struct.opposite_struct.position
      }
      struct.surface.create_entity {
        name = SpaceElevator.name_sound_train_start,
        position = struct.position
      }
      struct.opposite_struct.surface.create_entity {
        name = SpaceElevator.name_sound_train_start,
        position = struct.opposite_struct.position
      }
    end

    -- sounds
    struct.surface.create_entity {
      name = SpaceElevator.name_sound_carriage_up,
      position = struct.position
    }
    struct.opposite_struct.surface.create_entity {
      name = SpaceElevator.name_sound_carriage_down,
      position = struct.opposite_struct.position
    }

    new_carriage = struct.opposite_struct.surface.create_entity {
      name = carriage.name,
      position = Util.vectors_add(SpaceElevator.space_elevator_output[struct.direction], struct.position),
      direction = spawn_direction,
      force = carriage.force,
      color = carriage.color,
      quality = carriage.quality,
    }
    ---@cast new_carriage -?
    local costs = SpaceElevator.carriage_transfer_costs(struct, carriage)
    --Log.debug(carriage.name.." parts_cost " .. parts_cost .. " inventory_size " .. inventory_size)
    primary.parts = primary.parts - costs.parts_cost
    primary.lua_energy = primary.lua_energy + costs.energy_change

    SpaceElevator.carriage_transfer_contents(carriage, new_carriage)

    if not struct.tug then
      -- place a "tug" behind the carriage
      SpaceElevator.create_tug(struct, carriage)
    end
    script.raise_script_built { entity = new_carriage } -- Raise built event for compatibility with mods like Electric Train

    -- Save the old train speed before removing the carriage
    local old_train_speed = carriage.train.speed

    -- Is this a brand new train?
    if not (struct.carriage_ahead and struct.carriage_ahead.valid) then
      local schedule_old = carriage.train.get_schedule()
      local records = schedule_old.get_records()

      local current_stop_index = schedule_old.current

      -- Remove all rail based stops as these cause a crash
      for i = #records, 1, -1 do
        if records[i].rail then
          if records[i].rail == struct.station.connected_rail and current_stop_index == i then -- wait condition for blocked trains
            -- just back the schedule up to the elevator station to be handled later
            current_stop_index = current_stop_index - 1
          elseif i == current_stop_index then
            if current_stop_index == #records then
              current_stop_index = 1
            end
          elseif i < current_stop_index then
            current_stop_index = current_stop_index - 1
          end
          if not records[i].temporary then
            error("non-temporary rail based stops will crash due to changing surface.")
            -- The only way to add these is through the API. If we were to remove them, our record indexing will be off.
          end
          table.remove(records, i)
        end
      end

      local current_record = records[current_stop_index]
      --it is possible to set a train to automatic while manually driving causing it to drift through the elevator with no schedule.
      if not carriage.train.manual_mode and current_record and current_record.station == struct.station.backer_name then
        if current_record.temporary then
          --remove this scheduled stop if its temporary as the native scheduler does not.
          table.remove(records, current_stop_index)
          if current_stop_index > #records then
            current_stop_index = 1
          end
        else
          current_stop_index = (current_stop_index % #records) + 1
        end
      end

      --setup the new schedule
      local schedule_new = new_carriage.train.get_schedule()
      local group = schedule_old.group
      if group then
        schedule_new.group = schedule_old.group
        --setting the group sets non-temporary schedule records and interrupts. Add remaining temporary stops.
        for i = 1, #records do
          local record = records[i]
          if record.temporary then
            record.index = { schedule_index = i }
            schedule_new.add_record(record)
          end
        end
      else
        schedule_new.set_records(records)
        schedule_new.set_interrupts(schedule_old.get_interrupts())
      end
      if #records > 0 then
        schedule_new.go_to_station(current_stop_index)
      end

      carriage.train.schedule = nil

      -- Save the old train id before removing the carriage
      struct.old_train_id = carriage.train.id

      -- Raise on_train_teleport_started event after the first carriage is created on the new surface.
      script.raise_event(SpaceElevator.on_train_teleport_started_event,
        {
          train = new_carriage.train,
          old_train_id_1 = struct.old_train_id,
          old_surface_index = struct.surface.index,
          teleporter = struct.entity
        })
    end

    script.raise_script_destroy { entity = carriage, cloned = true } -- Raise destroy event for compatibility with Vehicle Wagon and others
    if carriage.valid then
      carriage.destroy()                                             -- This also sets the "behind" train to manual mode
    end
    struct.carriage_ahead = new_carriage
    if carriage_behind then
      struct.carriage_behind = carriage_behind
    else -- This is the last carriage of this train
      SpaceElevator.finish_teleport(struct)
    end

    local new_train_is_backwards
    if struct.tug then
      new_train_is_backwards = new_carriage.train.front_stock == struct.tug
    else
      new_train_is_backwards = #new_carriage.train.carriages > 1 and new_carriage.train.front_stock == new_carriage
    end
    local speed_direction = new_train_is_backwards and -1 or 1

    -- After placing new carriages or removing the tug, Factorio will set the train to manual and to the 1st station in its schedule.
    -- We put it back to how it was before.
    if carriage_ahead_current_stop then
      new_carriage.train.go_to_station(carriage_ahead_current_stop)
    end
    new_carriage.train.manual_mode = carriage_ahead_manual_mode

    -- Adding carriage to a train instantly slows it down.
    -- Also changing from manual to auto instantly stops it.
    -- Instead, bring it back to the speed it was.
    if new_carriage.train.speed == 0 then
      new_carriage.train.speed = speed_direction * math.abs(old_train_speed)
    else
      new_carriage.train.speed = util.sign(new_carriage.train.speed) * math.abs(old_train_speed)
    end

    -- For trains going to a train limit stop,
    -- when attaching a new carriage, the "new" train will try repathing *before* the stop unreserves the spot from the old train who has now disappeared.
    -- The train will be stuck in destination full until Factorio checks again (every 2 seconds).
    -- Check this train for manual repath on the next tick.
    -- Tick task has to be created after potential destruction of the tug (to keep new_carriage.train valid).
    if not new_carriage.train.manual_mode then
      local tick_task = new_tick_task("train-check-destination-full") --[[@as TrainCheckDestinationFullTickTask]]
      tick_task.delay_until = tick + 1
      tick_task.train = new_carriage.train
      tick_task.speed = speed_direction * math.abs(old_train_speed)
    end
    return
  else
    -- check if train is still there, may have been destroyed or moved
    if offset_tick % (SpaceElevator.teleport_next_tick_frequency * 15) == 0 then
      local carriage_bounding_box = util.rotate_box(carriage.bounding_box, carriage.position)
      local carriage_side = (struct.direction == defines.direction.east) and carriage_bounding_box.right_bottom or
          carriage_bounding_box.left_top
      if not Util.position_in_rect(struct.main.bounding_box, carriage_side) then
        SpaceElevator.finish_teleport(struct)
        return
      end
    end

    if not carriage_ahead then
      -- New train, but we can't teleport it.
      -- It will reach the elevator station and maybe move on to the next station in its schedule, causing station skip or even making the train go backwards.
      -- Prevent this by setting an infinite wait condition on the elevator station.
      -- We will remove it after teleport.
      local schedule = carriage.train.get_schedule()
      if schedule and not carriage.train.manual_mode then                                       -- Could be wagons only or manually driven
        local current_record = schedule.get_record({ schedule_index = schedule.current })
        if not current_record.rail or current_record.rail ~= struct.station.connected_rail then -- did we already add this?
          -- use a temporary schedule record that points to a rail segment
          -- can't use non-temporary as such a stop will be added to the group
          local temp_stop = {
            rail = struct.station.connected_rail,
            wait_conditions = { { type = "time", ticks = 9999999 * 60, compare_type = "and" } },
            temporary = true,
            index = { schedule_index = schedule.current + 1 }
          }
          schedule.add_record(temp_stop)
          schedule.go_to_station(schedule.current + 1)
        end
      end
    end
  end
end

---@param tick_task TrainCheckDestinationFullTickTask
function SpaceElevator.train_check_destination_full(tick_task)
  local train = tick_task.train
  if train.valid and train.state == defines.train_state.destination_full then
    -- Manually repath and reset speed.
    train.recalculate_path()
    if train.state ~= defines.train_state.destination_full and train.state ~= defines.train_state.no_path then
      train.speed = tick_task.speed
    end
  end
end

---@param carriage LuaEntity
---@param new_carriage LuaEntity
function SpaceElevator.carriage_transfer_contents(carriage, new_carriage)
  Util.transfer_equipment_grid(carriage, new_carriage)
  if carriage.type == "cargo-wagon" then
    Util.transfer_inventory_filters(carriage, new_carriage, defines.inventory.cargo_wagon)
    Util.move_inventory_items(carriage.get_inventory(defines.inventory.cargo_wagon),
      new_carriage.get_inventory(defines.inventory.cargo_wagon))
  elseif carriage.type == "fluid-wagon" then
    Util.transfer_fluids(carriage, new_carriage)
  elseif carriage.type == "locomotive" then
    Util.transfer_burner(carriage, new_carriage) -- Includes fuel and result inventories
  elseif carriage.type == "artillery-wagon" then
    Util.transfer_inventory_filters(carriage, new_carriage, defines.inventory.artillery_wagon_ammo)
    Util.move_inventory_items(carriage.get_inventory(defines.inventory.artillery_wagon_ammo),
      new_carriage.get_inventory(defines.inventory.artillery_wagon_ammo))
    if carriage.kills then
      new_carriage.kills = carriage.kills
    end
    if carriage.damage_dealt then
      new_carriage.damage_dealt = carriage.damage_dealt
    end
  elseif carriage.type == "infinity-cargo-wagon" then
    Util.transfer_inventory_filters(carriage, new_carriage, defines.inventory.cargo_wagon)
    Util.move_inventory_items(carriage.get_inventory(defines.inventory.cargo_wagon),
      new_carriage.get_inventory(defines.inventory.cargo_wagon))
    Util.transfer_infinity_container(carriage, new_carriage)
  end

  if carriage.backer_name then
    new_carriage.backer_name = carriage.backer_name
  end
  new_carriage.last_user = carriage.last_user
  new_carriage.health = carriage.health
  new_carriage.minable = carriage.minable
  new_carriage.minable_flag = carriage.minable_flag
  new_carriage.rotatable = carriage.rotatable
  new_carriage.destructible = carriage.destructible
  new_carriage.enable_logistics_while_moving = carriage.enable_logistics_while_moving
  new_carriage.operable = carriage.operable
  new_carriage.custom_status = carriage.custom_status
  new_carriage.copy_color_from_train_stop = carriage.copy_color_from_train_stop

  local driver = carriage.get_driver()
  carriage.set_driver(nil)
  if driver then
    if driver.object_name ~= "LuaPlayer" then -- In some cases players can control trains directly e.g. editor
      driver = teleport_character_to_surface(driver, new_carriage.surface, new_carriage.position)
    end
    new_carriage.set_driver(driver)
  end

  if remote.interfaces["VehicleWagon2"] then
    local wagon_data = remote.call("VehicleWagon2", "get_wagon_data", carriage)
    if wagon_data then
      remote.call("VehicleWagon2", "set_wagon_data", new_carriage, wagon_data)
    end
  end
end

---@param struct SpaceElevatorInfo
---@return number
function SpaceElevator.get_maintenance_per_stack_up(struct)
  return SpaceElevator.maintenance_per_stack_up *
      (SpaceElevator.maintenance_min_multiplier + (1 - SpaceElevator.maintenance_min_multiplier) * SpaceElevator.struct_radius(struct) / 10000)
end

---@param struct SpaceElevatorInfo
---@return number
function SpaceElevator.get_maintenance_per_stack_down(struct)
  return SpaceElevator.maintenance_per_stack_down *
      (SpaceElevator.maintenance_min_multiplier + (1 - SpaceElevator.maintenance_min_multiplier) * SpaceElevator.struct_radius(struct) / 10000)
end

---@param struct SpaceElevatorInfo
---@return number
function SpaceElevator.get_energy_per_stack_up(struct)
  return SpaceElevator.energy_per_stack_up *
      (SpaceElevator.maintenance_min_multiplier + (1 - SpaceElevator.maintenance_min_multiplier) * SpaceElevator.struct_radius(struct) / 10000)
end

---@param struct SpaceElevatorInfo
---@return number
function SpaceElevator.get_energy_per_stack_down(struct)
  return SpaceElevator.energy_per_stack_down *
      (SpaceElevator.maintenance_min_multiplier + (1 - SpaceElevator.maintenance_min_multiplier) * SpaceElevator.struct_radius(struct) / 10000)
end

-- returns 2 values
---@param struct SpaceElevatorInfo
---@param carriage LuaEntity
---@return {parts_cost: number, energy_change: number}
function SpaceElevator.carriage_transfer_costs(struct, carriage)
  local inventory_size = SpaceElevator.get_inventory_size(carriage.name)
  return SpaceElevator.inventory_transfer_costs(struct, inventory_size)
end

-- returns 2 values
---@param struct SpaceElevatorInfo
---@param player LuaPlayer
---@return { parts_cost: number, energy_change: number }
function SpaceElevator.player_transfer_costs(struct, player)
  local inventory_size = 10 + #player.get_main_inventory()
  return SpaceElevator.inventory_transfer_costs(struct, inventory_size)
end

-- returns 2 values
---@param struct SpaceElevatorInfo
---@param inventory_size uint
---@return {parts_cost: number, energy_change: number}
function SpaceElevator.inventory_transfer_costs(struct, inventory_size)
  local parts_cost, energy_change
  if Zone.is_solid(struct.zone) then
    parts_cost = inventory_size * SpaceElevator.get_maintenance_per_stack_up(struct)
    energy_change = inventory_size * SpaceElevator.get_energy_per_stack_up(struct)
  else
    parts_cost = inventory_size * SpaceElevator.get_maintenance_per_stack_down(struct)
    energy_change = inventory_size * SpaceElevator.get_energy_per_stack_down(struct)
  end
  return { parts_cost = parts_cost, energy_change = energy_change }
end

---@param struct SpaceElevatorInfo
function SpaceElevator.clear_text(struct)
  if not struct.text then return end
  struct.text.destroy() -- Safe to call even when invalid
end

---@param struct SpaceElevatorInfo
---@param text string
---@param color Color
function SpaceElevator.set_text(struct, text, color)
  SpaceElevator.clear_text(struct)
  struct.text = rendering.draw_text {
    text = text,
    surface = struct.surface,
    target = {
      entity = struct.main,
      offset = { 0, -4.5 },
    },
    color = color or { 1, 1, 1 },
    alignment = "center",
    scale = 1.5,
    only_in_alt_mode = true
  }
end

---@param struct SpaceElevatorInfo
function SpaceElevator.clear_icon(struct)
  if not struct.icon then return end
  struct.icon.destroy() -- Safe to call even when invalid
end

---@param struct SpaceElevatorInfo
---@param sprite string
function SpaceElevator.set_icon(struct, sprite)
  SpaceElevator.clear_icon(struct)
  struct.icon = rendering.draw_sprite {
    sprite           = sprite,
    surface          = struct.surface,
    target           = {
      entity = struct.main,
      offset = { 0, -5 },
    },
    only_in_alt_mode = false,
    x_scale          = 0.5,
    y_scale          = 0.5
  }
end

-- check if there are any trains that would prevent track removal.
---@param struct SpaceElevatorInfo
---@return boolean
function SpaceElevator.space_elevator_can_mine_pair(struct)
  return SpaceElevator.space_elevator_can_mine_single(struct) and
      SpaceElevator.space_elevator_can_mine_single(struct.opposite_struct)
end

-- check if there are any trains that would prevent track removal.
---@param struct SpaceElevatorInfo
---@return boolean
function SpaceElevator.space_elevator_can_mine_single(struct)
  return struct.main.surface.count_entities_filtered { type = SpaceElevator.stock_types, area = struct.main.bounding_box, limit = 1 } ==
      0
end

---@param event EventData.on_pre_player_mined_item|EventData.on_robot_pre_mined Event data
function SpaceElevator.on_pre_mined(event)
  if event.entity.name == SpaceElevator.name_space_elevator then
    local entity = event.entity
    local struct = SpaceElevator.from_entity(entity)
    if not struct then return end
    if not SpaceElevator.space_elevator_can_mine_pair(struct) then
      -- cancel action
      --entity.minable = false -- does not work.
      struct.main.destroy()
      struct.main = struct.surface.create_entity {
        name = SpaceElevator.name_space_elevator,
        position = struct.position,
        direction = struct.direction,
        force = struct.force_name
      }
      SpaceElevator.draw_top(struct)
      struct.last_crafts = 0
      storage.space_elevators[struct.unit_number] = nil
      struct.unit_number = struct.main.unit_number
      storage.space_elevators[struct.unit_number] = struct
    else
      local primary = SpaceElevator.struct_primary(struct)
      local parts = primary.parts * 0.9 -- lose 10%
      primary.parts = 0
      if parts >= 1 then
        if event.player_index then
          parts = parts - game.get_player(event.player_index).insert({ name = SpaceElevator.name_part, count = parts })
        end
        if parts >= 1 then
          primary.surface.spill_item_stack {
            position = primary.position,
            stack = { name = SpaceElevator.name_part, count = parts },
            enable_looted = true,
            force = struct.force_name,
            allow_belts = false
          }
        end
      end
    end
  end
end

Event.addListener(defines.events.on_pre_player_mined_item, SpaceElevator.on_pre_mined)
Event.addListener(defines.events.on_robot_pre_mined, SpaceElevator.on_pre_mined)

---@param struct SpaceElevatorInfo
function SpaceElevator.space_elevator_destroy(struct)
  local area = Util.area_add_position(prototypes.entity[SpaceElevator.name_space_elevator].collision_box, struct
    .position)
  --[[rendering.draw_rectangle{
    surface = struct.surface,
    left_top = area.left_top,
    right_bottom = area.right_bottom,
    color = {0.5,0,0.0, 0.5},
    time_to_live = 60,
    filled = true
  }]]
  if struct.tug and struct.tug.valid then struct.tug.destroy() end
  if struct.surface.valid then
    local carriages = struct.surface.find_entities_filtered { type = SpaceElevator.stock_types, area = area }
    for _, carriage in pairs(carriages) do
      carriage.die()
    end
    local carriages = struct.surface.find_entities_filtered { type = SpaceElevator.stock_types, area = area }
    for _, carriage in pairs(carriages) do
      carriage.destroy()
    end
  end
  if struct.collider and struct.collider.valid then struct.collider.destroy() end
  if struct.station and struct.station.valid then struct.station.destroy() end
  if struct.energy_interface and struct.energy_interface.valid then struct.energy_interface.destroy() end
  if struct.electric_pole and struct.electric_pole.valid then struct.electric_pole.destroy() end
  if struct.power_switch and struct.power_switch.valid then struct.power_switch.destroy() end
  for _, sub_entity in pairs(struct.sub_entities) do
    if sub_entity.valid then sub_entity.destroy() end
  end
  storage.space_elevators[struct.unit_number] = nil
  if struct.opposite_struct.main and struct.opposite_struct.main.valid then
    struct.opposite_struct.main.destroy()
  end
end

---@param value number
---@return Color
function SpaceElevator.colour_from_value(value)
  -- same red as danger icon, transition to orange, yellow, then light grey
  return {
    249,
    55 + (249 - 55) * math.max(0, math.min(1, 2 * value)),
    46 + (249 - 46) * math.max(0, math.min(1, -1 + 2 * value))
  }
end

---@param primary SpaceElevatorInfo
---@return number
function SpaceElevator.space_elevator_parts_per_second(primary)
  return SpaceElevator.maintenance_per_second *
      (SpaceElevator.maintenance_min_multiplier + (1 - SpaceElevator.maintenance_min_multiplier) * SpaceElevator.struct_radius(primary) / 10000)
end

---@param primary SpaceElevatorInfo
function SpaceElevator.clear_all_icons_and_text(primary)
  SpaceElevator.clear_text(primary)
  SpaceElevator.clear_text(primary.opposite_struct)
  SpaceElevator.clear_icon(primary)
  SpaceElevator.clear_icon(primary.opposite_struct)
end

---@param primary SpaceElevatorInfo
---@param icon_string string
function SpaceElevator.set_parts_icon_and_text(primary, icon_string)
  local str_parts = primary.parts <= 0 and "0" or string.format("%.0f", primary.parts)
  local str_parts_needed = string.format("%.0f", primary.parts_needed)
  SpaceElevator.set_text(primary, str_parts .. "/" .. str_parts_needed,
    SpaceElevator.colour_from_value(primary.parts / primary.parts_needed))
  SpaceElevator.set_text(primary.opposite_struct, str_parts .. "/" .. str_parts_needed,
    SpaceElevator.colour_from_value(primary.parts / primary.parts_needed))
  SpaceElevator.set_icon(primary, icon_string)
  SpaceElevator.set_icon(primary.opposite_struct, icon_string)
end

---@param primary SpaceElevatorInfo
function SpaceElevator.connect_wires(primary)
  if primary.power_switch and primary.electric_pole and primary.opposite_struct.electric_pole
      and primary.power_switch.valid and primary.electric_pole.valid and primary.opposite_struct.electric_pole.valid then
    primary.electric_pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
        .connect_to(primary.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_left_copper, true),
          false, defines.wire_origin.script)
    primary.opposite_struct.electric_pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
        .connect_to(primary.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_right_copper, true),
          false, defines.wire_origin.script)
    primary.power_switch.power_switch_state = true
    primary.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_red, true)
        .connect_to(
          primary.opposite_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_red, true), false,
          defines.wire_origin.script)
    primary.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        .connect_to(
          primary.opposite_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_green, true), false,
          defines.wire_origin.script)
  end
end

---@param primary SpaceElevatorInfo
function SpaceElevator.disconnect_wires(primary)
  if primary.power_switch and primary.electric_pole and primary.opposite_struct.electric_pole
      and primary.power_switch.valid and primary.electric_pole.valid and primary.opposite_struct.electric_pole.valid then
    primary.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_left_copper, true).disconnect_all(
      defines.wire_origin.script)
    primary.power_switch.get_wire_connector(defines.wire_connector_id.power_switch_right_copper, true).disconnect_all(
      defines.wire_origin.script)
    primary.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_red, true)
        .disconnect_from(
          primary.opposite_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_red, true),
          defines.wire_origin.script)
    primary.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        .disconnect_from(
          primary.opposite_struct.electric_pole.get_wire_connector(defines.wire_connector_id.circuit_green, true),
          defines.wire_origin.script)
  end
end

---@param primary SpaceElevatorInfo
function SpaceElevator.space_elevator_maintain_parts(primary)
  primary.parts_needed = SpaceElevator.parts_per_radius * SpaceElevator.struct_radius(primary)

  if primary.built then
    primary.parts = math.max(0, primary.parts - SpaceElevator.space_elevator_parts_per_second(primary))
    if primary.parts >= primary.parts_needed then --don't need parts
      primary.main.active = false
      primary.opposite_struct.main.active = false
      return -- no need to check further.
    end      -- below this, need parts
    primary.main.active = true
    primary.opposite_struct.main.active = true
    SpaceElevator.connect_wires(primary) -- prevent shift-left-click shenanigans
    if primary.parts > primary.parts_needed * SpaceElevator.parts_display_threshold then
      SpaceElevator.clear_all_icons_and_text(primary)
      return -- the other thresholds are lower, so don't care.
    else     -- built, but less than threshold parts
      SpaceElevator.set_parts_icon_and_text(primary, "se-warning-parts")
    end
    if primary.parts <= 0 then
      game.forces[primary.force_name].print({ "space-exploration.space-elevator-broken", util.gps_tag(
        primary.surface.name, primary.position) })
      primary.built = false
      SpaceElevator.disconnect_wires(primary)
      primary.energy_interface.power_usage = 0
      primary.opposite_struct.energy_interface.power_usage = 0
    end
  elseif primary.parts < primary.parts_needed then -- not built, and need more parts
    primary.main.active = true
    primary.opposite_struct.main.active = true
    SpaceElevator.set_parts_icon_and_text(primary, "se-danger-parts")
  else -- not built, but have enough parts
    primary.main.active = false
    primary.opposite_struct.main.active = false
    primary.built = true
    SpaceElevator.clear_all_icons_and_text(primary)
    SpaceElevator.connect_wires(primary)
  end
end

---@param primary SpaceElevatorInfo
---@param inputs LuaEntity[]
function SpaceElevator.take_energy_from(primary, inputs)
  local transfer = math.max(-primary.lua_energy, 0)
  local transfer_each = transfer / #inputs
  for _, input in pairs(inputs) do --sadly i think i need to check the EEIs every cycle to make sure there isn't any free energy being made.
    local transfer_individual = math.min(transfer_each, input.energy)
    primary.lua_energy = primary.lua_energy + transfer_individual
    input.power_usage = transfer_individual / 60
  end
end

---@param primary SpaceElevatorInfo
function SpaceElevator.space_elevator_maintain_energy(primary)
  -- do power check
  if primary.built == true and primary.energy_interface and primary.opposite_struct.energy_interface then
    local interface_energy = primary.energy_interface.energy + primary.opposite_struct.energy_interface.energy
    primary.lua_energy = primary.lua_energy - math.min(SpaceElevator.energy_passive_draw, interface_energy)
    SpaceElevator.take_energy_from(primary, { primary.energy_interface, primary.opposite_struct.energy_interface })
    primary.total_energy = primary.lua_energy + interface_energy
    if primary.total_energy < SpaceElevator.energy_min then
      SpaceElevator.set_icon(primary, "se-danger-charge")
      SpaceElevator.set_icon(primary.opposite_struct, "se-danger-charge")
    elseif primary.parts_needed and primary.parts > primary.parts_needed * SpaceElevator.parts_display_threshold then
      SpaceElevator.clear_icon(primary)
      SpaceElevator.clear_icon(primary.opposite_struct)
    end
  elseif primary.energy_interface and primary.opposite_struct.energy_interface then
    primary.total_energy = primary.lua_energy + primary.energy_interface.energy +
        primary.opposite_struct.energy_interface.energy
  end
end

---@param struct SpaceElevatorInfo
function SpaceElevator.space_elevator_maintain(struct)
  local primary = SpaceElevator.struct_primary(struct)
  if struct.main.products_finished > struct.last_crafts then
    primary.parts = primary.parts + struct.main.products_finished - struct.last_crafts
  end
  struct.last_crafts = struct.main.products_finished

  if struct.is_primary then
    SpaceElevator.space_elevator_maintain_parts(primary)
    SpaceElevator.space_elevator_maintain_energy(primary)
  end

  if not primary.built or ((primary.total_energy or 0) < SpaceElevator.energy_min) then
    -- Do not remember train in elevator (in case it ends up going backwards) & cut train in half if it is in the middle of transport
    struct.carriage_behind = nil
    struct.carriage_ahead = nil
    if struct.tug and struct.tug.valid then struct.tug.destroy() end
    return
  end
end

---@param carriage_a LuaEntity
---@return 1|-1
function SpaceElevator.train_forward_sign(carriage_a)
  -- get if the train forward direction is the same as the cariage direction
  local sign = 1
  if #carriage_a.train.carriages == 1 then return sign end
  local carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.front)
  if not carriage_b then
    carriage_b = carriage_a.get_connected_rolling_stock(defines.rail_direction.back)
    sign = -sign
  end
  -- front to back, if b is in front of the reference carriage and b is detected first then the carriage matches the train
  for _, carriage in pairs(carriage_a.train.carriages) do
    if carriage == carriage_b then return sign end
    if carriage == carriage_a then return -sign end
  end
end

---@param carriage_a LuaEntity
---@param carriage_a_direction 1|-1
---@param carriage_b LuaEntity
---@param carriage_b_direction 1|-1
function SpaceElevator.hypertrain_sync_speed(carriage_a, carriage_a_direction, carriage_b, carriage_b_direction)
  local train_a = carriage_a.train
  local train_b = carriage_b.train
  local total_weight = train_a.weight + train_b.weight -- weigh the hypertrain
  local average_speed = (
    (train_a.weight * math.abs(train_a.speed)) +
    (train_b.weight * math.abs(train_b.speed))
  ) / total_weight
  average_speed = math.min(average_speed, SpaceElevator.max_train_speed)

  train_a.speed = average_speed * carriage_a_direction * SpaceElevator.train_forward_sign(carriage_a)
  train_b.speed = average_speed * carriage_b_direction * SpaceElevator.train_forward_sign(carriage_b)
end

---@param struct SpaceElevatorInfo
function SpaceElevator.hypertrain_manage_speed(struct)
  -- if the train is split, try to have a consistent speed through the elevator
  if struct.carriage_behind and struct.carriage_behind.valid and struct.carriage_ahead and struct.carriage_ahead.valid then
    -- keep the train speed above a minimum value.
    if math.abs(struct.carriage_ahead.train.speed) < SpaceElevator.passive_train_speed / 4 and
        struct.carriage_ahead.train.state == defines.train_state.on_the_path
    then
      struct.carriage_ahead.train.speed =
          SpaceElevator.passive_train_speed / 4 *
          SpaceElevator.elevator_east_sign(struct) *
          SpaceElevator.carriage_east_sign(struct.carriage_ahead) *
          SpaceElevator.train_forward_sign(struct.carriage_ahead)
    end

    if math.abs(struct.carriage_ahead.train.speed) < SpaceElevator.passive_train_speed and
        (
          struct.carriage_ahead.train.manual_mode and
          (
            Util.vectors_delta_length(struct.carriage_ahead.train.front_stock.position, struct.position) < SpaceElevator.space_elevator_hypertrain_radius and
            Util.vectors_delta_length(struct.carriage_ahead.train.back_stock.position, struct.position) < SpaceElevator.space_elevator_hypertrain_radius
          )
        ) then
      struct.carriage_ahead.train.speed =
          SpaceElevator.passive_train_speed *
          SpaceElevator.elevator_east_sign(struct) *
          SpaceElevator.carriage_east_sign(struct.carriage_ahead) *
          SpaceElevator.train_forward_sign(struct.carriage_ahead)
    end

    if struct.carriage_ahead == struct.tug then
      if struct.tug.train.state == defines.train_state.no_path then
        struct.tug.train.manual_mode = true
      end
      struct.tug.train.speed = 0.5
    else
      if not struct.carriage_behind.train.manual_mode then
        struct.carriage_behind.train.manual_mode = true -- Force "behind" train to manual mode in case a player set it to automatic. If we try to set the speed of an automatic train it will crash on direction reverse.
      end
      SpaceElevator.hypertrain_sync_speed(
        struct.carriage_behind,
        SpaceElevator.elevator_east_sign(struct) * SpaceElevator.carriage_east_sign(struct.carriage_behind),
        struct.carriage_ahead,
        SpaceElevator.elevator_east_sign(struct) * SpaceElevator.carriage_east_sign(struct.carriage_ahead)
      )
      if math.abs(struct.carriage_ahead.train.speed) > SpaceElevator.max_train_speed then
        struct.carriage_ahead.train.speed = SpaceElevator.max_train_speed * util.sign(struct.carriage_ahead.train.speed)
      end
      -- if the carriage behind is falling behind, speed up the rear train.
      local distance = util.vectors_delta_length(struct.carriage_behind.position, struct.position)
      if distance > 12 then
        local compensator = (distance - 12) / 12
        struct.carriage_ahead.train.speed = struct.carriage_ahead.train.speed * (1 - compensator)
        struct.carriage_behind.train.speed = struct.carriage_behind.train.speed * (1 + compensator) +
            util.sign(struct.carriage_behind.train.speed) * 0.1
      end
    end
  elseif struct.tug and struct.tug.valid then
    struct.tug.destroy()
  end
end

---@param struct SpaceElevatorInfo
---@return 1|-1
function SpaceElevator.elevator_east_sign(struct)
  return struct.direction == defines.direction.east and 1 or -1
end

---@param carriage LuaEntity
---@return 1|-1
function SpaceElevator.carriage_east_sign(carriage)
  return carriage.orientation < 0.5 and 1 or -1
end

---@param struct SpaceElevatorInfo
---@param tick uint Current tick
function SpaceElevator.space_elevator_tick(struct, tick)
  if not (struct.main and struct.main.valid and struct.opposite_struct.main and struct.opposite_struct.main.valid) then
    SpaceElevator.space_elevator_destroy(struct)
    return
  end

  -- Add to maintenance
  local offset_tick = tick + struct.unit_number
  if offset_tick % 60 == 0 then
    SpaceElevator.space_elevator_maintain(struct)
    -- replace the train detector collider
    if not (struct.collider and struct.collider.valid) then
      if struct.surface.can_place_entity {
            name = SpaceElevator.name_space_elevator_train_collider,
            position = Util.vectors_add(struct.position, SpaceElevator.space_elevator_collider_position[struct.direction])
          }
      then
        struct.collider = struct.surface.create_entity {
          name = SpaceElevator.name_space_elevator_train_collider,
          position = Util.vectors_add(struct.position, SpaceElevator.space_elevator_collider_position[struct.direction]),
          force = "neutral"
        }
      end
    end
  end

  local primary = SpaceElevator.struct_primary(struct)
  if primary.built then
    local has_enough_energy = (primary.total_energy or 0) >= SpaceElevator.energy_min
    -- if there is already a carriage ahead, i.e. the train is half way though, teleport the next carriage
    -- if there is no carriage ahead, only start on a new train if the minimum energy is satisfied
    if offset_tick % SpaceElevator.teleport_next_tick_frequency == 0 and (has_enough_energy or struct.carriage_ahead) then
      SpaceElevator.space_elevator_teleport_next(struct, primary, tick, offset_tick)
    end
  end

  SpaceElevator.hypertrain_manage_speed(struct)
end

---@param event EventData.on_tick Event data
function SpaceElevator.on_tick(event)
  for _, struct in pairs(storage.space_elevators) do
    SpaceElevator.space_elevator_tick(struct, event.tick)
  end
end

Event.addListener(defines.events.on_tick, SpaceElevator.on_tick)

function SpaceElevator.on_init()
  storage.space_elevators = {}
end

Event.addListener("on_init", SpaceElevator.on_init, true)

return SpaceElevator
