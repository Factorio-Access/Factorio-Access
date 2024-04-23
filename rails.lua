--Here: Functions relating to rail topics including rail info and analysis, rail signals, and the rail builder system
--Does not include event handlers
---@diagnostic disable: assign-type-mismatch

local util = require('util')
local fa_utils = require('fa-utils')
local fa_mining_tools = require("mining-tools")
local dirs = defines.direction

local fa_rail_builder = {}
local fa_rails = {}

--Key information about rail units. 
function fa_rails.rail_ent_info(pindex, ent, description)  
   local result = ""
   local is_end_rail = false
   local is_horz_or_vert = false
   
   --Check if end rail: The rail is at the end of its segment and is also not connected to another rail
   is_end_rail, end_rail_dir, build_comment = fa_rails.check_end_rail(ent,pindex)
   if is_end_rail then
      --Further check if it is a single rail
      if build_comment == "single rail" then
         result = result .. "Single "
      end
      result = result .. "End rail "
   else
      result = result .. "Rail "
   end
      
   --Explain the rail facing direction
   if ent.name == "straight-rail" and is_end_rail then
      result = result .. " straight "
      if end_rail_dir == dirs.north then
         result = result .. " facing North "
      elseif end_rail_dir == dirs.northeast then
         result = result .. " facing Northeast "
      elseif end_rail_dir == dirs.east then
         result = result .. " facing East "
      elseif end_rail_dir == dirs.southeast then
         result = result .. " facing Southeast "
      elseif end_rail_dir == dirs.south then
         result = result .. " facing South "
      elseif end_rail_dir == dirs.southwest then
         result = result .. " facing Southwest "
      elseif end_rail_dir == dirs.west then
         result = result .. " facing West "
      elseif end_rail_dir == dirs.northwest then
         result = result .. " facing Northwest "
      end
      
   elseif ent.name == "straight-rail" and is_end_rail == false then
      if ent.direction == dirs.north or ent.direction == dirs.south then --always reports 0 it seems
         result = result .. " vertical "
         is_horz_or_vert = true
      elseif ent.direction == dirs.east or ent.direction == dirs.west then --always reports 2 it seems
         result = result .. " horizontal "
         is_horz_or_vert = true
         
      elseif ent.direction == dirs.northeast then
         result = result .. " on falling diagonal, left half "
      elseif ent.direction == dirs.southwest then
         result = result .. " on falling diagonal, right half "
      elseif ent.direction == dirs.southeast then
         result = result .. " on rising diagonal, left half "
      elseif ent.direction == dirs.northwest then
         result = result .. " on rising diagonal, right half "
      end
   
   elseif ent.name == "curved-rail" and is_end_rail == true then
      result = result .. " curved "
      if end_rail_dir == dirs.north then
         result = result .. " facing North "
      elseif end_rail_dir == dirs.northeast then
         result = result .. " facing Northeast "
      elseif end_rail_dir == dirs.east then
         result = result .. " facing East "
      elseif end_rail_dir == dirs.southeast then
         result = result .. " facing Southeast "
      elseif end_rail_dir == dirs.south then
         result = result .. " facing South "
      elseif end_rail_dir == dirs.southwest then
         result = result .. " facing Southwest "
      elseif end_rail_dir == dirs.west then
         result = result .. " facing West "
      elseif end_rail_dir == dirs.northwest then
         result = result .. " facing Northwest "
      end
   
   elseif ent.name == "curved-rail" and is_end_rail == false then
      result = result .. " curved "
      if ent.direction == dirs.north then --0
         result = result ..  " facing south and falling diagonal "
      elseif ent.direction == dirs.northeast then
         result = result ..  " facing south and rising diagonal "
      elseif ent.direction == dirs.east then
         result = result ..  " facing west  and rising diagonal "
      elseif ent.direction == dirs.southeast then
         result = result ..  " facing west  and falling diagonal "
      elseif ent.direction == dirs.south then
         result = result ..  " facing north and falling diagonal "
      elseif ent.direction == dirs.southwest then
         result = result ..  " facing north and rising diagonal "
      elseif ent.direction == dirs.west then
         result = result ..  " facing east  and rising diagonal "
      elseif ent.direction == dirs.northwest then --7
         result = result ..  " facing east  and falling diagonal "
      end
   end
   
   --Check if intersection
   if fa_rails.is_intersection_rail(ent, pindex) then
      result = result .. ", intersection " 
   end
   --Check if at junction: The rail has at least 3 connections
   local connection_count = fa_rails.count_rail_connections(ent)
   if connection_count > 2 then
      result = result .. ", fork "
   end
   
   --Check if it has rail signals 
   local chain_s_count = 0
   local rail_s_count = 0
   local signals = ent.surface.find_entities_filtered{position = ent.position, radius = 2, name = "rail-chain-signal"}
   for i,s in ipairs(signals) do
      chain_s_count = chain_s_count + 1
      rendering.draw_circle{color = {0.5, 0.5, 1},radius = 2,width = 2,target = ent,surface = ent.surface,time_to_live = 90}
   end
   
   signals = ent.surface.find_entities_filtered{position = ent.position, radius = 2, name = "rail-signal"}
   for i,s in ipairs(signals) do
      rail_s_count = rail_s_count + 1
      rendering.draw_circle{color = {0.5, 0.5, 1},radius = 2,width = 2,target = ent,surface = ent.surface,time_to_live = 90}
   end
   
   if chain_s_count + rail_s_count == 0 then
      --(nothing)
   elseif chain_s_count + rail_s_count == 1 then
      result = result .. " with one signal, "
   elseif chain_s_count + rail_s_count == 2 then
      result = result .. " with a pair of signals, "
   elseif chain_s_count + rail_s_count > 2 then
      result = result .. " with many signals, "
   end
   
   --Check if there is a train stop nearby, to announce station spaces
   if is_horz_or_vert then
      local stop = nil
      local segment_ent_1 = ent.get_rail_segment_entity(defines.rail_direction.front, false)
      local segment_ent_2 = ent.get_rail_segment_entity(defines.rail_direction.back, false)
      if segment_ent_1 ~= nil and segment_ent_1.name == "train-stop" and util.distance(ent.position, segment_ent_1.position) < 45 then
         stop = segment_ent_1
      elseif segment_ent_2 ~= nil and segment_ent_2.name == "train-stop" and util.distance(ent.position, segment_ent_2.position) < 45 then
         stop = segment_ent_2
      end
      if stop == nil then
         return result
      end
      
      --Check if this rail is in the correct direction of the train stop
      local rail_dir_1 = segment_ent_1 == stop
      local rail_dir_2 = segment_ent_2 == stop
      local stop_dir = stop.connected_rail_direction
      local pairing_correct = false
      
      if rail_dir_1 and stop_dir == defines.rail_direction.front then
         --result = result .. ", pairing 1, "
         pairing_correct = true
      elseif rail_dir_1 and stop_dir == defines.rail_direction.back then
         --result = result .. ", pairing 2, "
         pairing_correct = false
      elseif rail_dir_2 and stop_dir == defines.rail_direction.front then
         --result = result .. ", pairing 3, "
         pairing_correct = false
      elseif rail_dir_2 and stop_dir == defines.rail_direction.back then
         --result = result .. ", pairing 4, "
         pairing_correct = true
      else
         result = result .. ", pairing error, "
         pairing_correct = false
      end
      
      if not pairing_correct then
         return result
      end
      
      --Count distance and determine railcar slot
      local dist = util.distance(ent.position, stop.position)
      --result = result .. " stop distance " .. dist
      if dist < 2 then
         result = result .. " station locomotive space front"
      elseif dist < 3 then
         result = result .. " station locomotive space middle"
      elseif dist < 5 then
         result = result .. " station locomotive space middle"
      elseif dist < 7 then
         result = result .. " station locomotive end and gap 1"
      elseif dist < 9 then
         result = result .. " station space 1 front"
      elseif dist < 11 then
         result = result .. " station space 1 middle"
      elseif dist < 13 then
         result = result .. " station space 1 end"
      elseif dist < 15 then
         result = result .. " station gap 2 and station space 2 front"
      elseif dist < 17 then
         result = result .. " station space 2 middle"
      elseif dist < 19 then
         result = result .. " station space 2 middle"
      elseif dist < 21 then
         result = result .. " station space 2 end and gap 3"
      elseif dist < 23 then
         result = result .. " station space 3 front"
      elseif dist < 25 then
         result = result .. " station space 3 middle"
      elseif dist < 27 then
         result = result .. " station space 3 end"
      elseif dist < 29 then
         result = result .. " station gap 4 and station space 4 front"
      elseif dist < 31 then
         result = result .. " station space 4 middle"
      elseif dist < 33 then
         result = result .. " station space 4 middle"
      elseif dist < 35 then
         result = result .. " station space 4 end and gap 5"
      elseif dist < 37 then
         result = result .. " station space 5 front"
      elseif dist < 39 then
         result = result .. " station space 5 middle"
      elseif dist < 41 then
         result = result .. " station space 5 end"
      elseif dist < 43 then
         result = result .. " station gap 6 and station space 6 front"
      elseif dist < 45 then
         result = result .. " station space 6 middle"
      end
   end
   
   return result
end

--Determines how many connections a rail has
function fa_rails.count_rail_connections(ent)
   local front_left_rail,r_dir_back,c_dir_back = ent.get_connected_rail{ rail_direction = defines.rail_direction.front,rail_connection_direction = defines.rail_connection_direction.left}
   local front_right_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.front,rail_connection_direction = defines.rail_connection_direction.right}
   local back_left_rail,r_dir_back,c_dir_back = ent.get_connected_rail{ rail_direction = defines.rail_direction.back,rail_connection_direction = defines.rail_connection_direction.left}
   local back_right_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.back,rail_connection_direction = defines.rail_connection_direction.right}
   local next_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.front,  rail_connection_direction = defines.rail_connection_direction.straight}
   local prev_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.back,   rail_connection_direction = defines.rail_connection_direction.straight}
   
   local connection_count = 0
   if next_rail ~= nil then
      connection_count = connection_count + 1
   end
   if prev_rail ~= nil then
      connection_count = connection_count + 1
   end
   if front_left_rail ~= nil then
      connection_count = connection_count + 1
   end
   if front_right_rail ~= nil then
      connection_count = connection_count + 1
   end
   if back_left_rail ~= nil then
      connection_count = connection_count + 1
   end
   if back_right_rail ~= nil then
      connection_count = connection_count + 1
   end
   return connection_count
end

--Determines how many connections a rail has
function fa_rails.list_rail_fork_directions(ent)
   local result = ""
   local front_left_rail,r_dir_back,c_dir_back = ent.get_connected_rail{ rail_direction = defines.rail_direction.front,rail_connection_direction = defines.rail_connection_direction.left}
   local front_right_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.front,rail_connection_direction = defines.rail_connection_direction.right}
   local back_left_rail,r_dir_back,c_dir_back = ent.get_connected_rail{ rail_direction = defines.rail_direction.back,rail_connection_direction = defines.rail_connection_direction.left}
   local back_right_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.back,rail_connection_direction = defines.rail_connection_direction.right}
   local next_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.front,  rail_connection_direction = defines.rail_connection_direction.straight}
   local prev_rail,r_dir_back,c_dir_back = ent.get_connected_rail{rail_direction = defines.rail_direction.back,   rail_connection_direction = defines.rail_connection_direction.straight}
   
   if next_rail ~= nil then
      result = result .. "straight forward, "
   end
   if front_left_rail ~= nil then
      result = result .. "left forward, "
   end
   if front_right_rail ~= nil then
      result = result .. "right forward, "
   end
   if prev_rail ~= nil then
      result = result .. "straight back, "
   end
   if back_left_rail ~= nil then
      result = result .. "left back, "
   end
   if back_right_rail ~= nil then
      result = result .. "right back, "
   end
   return result
end

--Determines if an entity is an end rail. Returns boolean is_end_rail, integer end rail direction, and string comment for errors.
function fa_rails.check_end_rail(check_rail, pindex)
   local is_end_rail = false
   local dir = -1
   local comment = "Check function error."
   
   --Check if the entity is a rail
   if check_rail == nil then
      is_end_rail = false
      comment = "Nil."
      return is_end_rail, -1, comment
   end
   if not check_rail.valid then
      is_end_rail = false
      comment = "Invalid."
      return is_end_rail, -1, comment
   end
   if not (check_rail.name == "straight-rail" or check_rail.name == "curved-rail") then
      is_end_rail = false
      comment = "Not a rail."
      return is_end_rail, -1, comment
   end
   
   --Check if end rail: The rail is at the end of its segment and has only 1 connection.
   end_rail_1, end_dir_1 = check_rail.get_rail_segment_end(defines.rail_direction.front)
   end_rail_2, end_dir_2 = check_rail.get_rail_segment_end(defines.rail_direction.back)
   local connection_count = fa_rails.count_rail_connections(check_rail)
   if (check_rail.unit_number == end_rail_1.unit_number or check_rail.unit_number == end_rail_2.unit_number) and connection_count < 2 then
      --End rail confirmed, get direction
      is_end_rail = true
      comment = "End rail confirmed."
      if connection_count == 0 then
         comment = "single rail"
      end
      if check_rail.name == "straight-rail" then
         local next_rail_straight,temp1,temp2 = check_rail.get_connected_rail{rail_direction = defines.rail_direction.front, 
               rail_connection_direction = defines.rail_connection_direction.straight}
         local next_rail_left,temp1,temp2 = check_rail.get_connected_rail{rail_direction = defines.rail_direction.front,
               rail_connection_direction = defines.rail_connection_direction.left}
         local next_rail_right,temp1,temp2 = check_rail.get_connected_rail{rail_direction = defines.rail_direction.front,
               rail_connection_direction = defines.rail_connection_direction.right}
         local next_rail = nil
         if next_rail_straight ~= nil then
            next_rail = next_rail_straight
         elseif next_rail_left ~= nil then
            next_rail = next_rail_left
         elseif next_rail_right ~= nil then
            next_rail = next_rail_right
         end
         local prev_rail_straight,temp1,temp2 = check_rail.get_connected_rail{rail_direction = defines.rail_direction.back,   
               rail_connection_direction = defines.rail_connection_direction.straight}
         local prev_rail_left,temp1,temp2 = check_rail.get_connected_rail{rail_direction = defines.rail_direction.back,   
               rail_connection_direction = defines.rail_connection_direction.left}
         local prev_rail_right,temp1,temp2 = check_rail.get_connected_rail{rail_direction = defines.rail_direction.back,   
               rail_connection_direction = defines.rail_connection_direction.right}
         local prev_rail = nil
         if prev_rail_straight ~= nil then
            prev_rail = prev_rail_straight
         elseif prev_rail_left ~= nil then
            prev_rail = prev_rail_left
         elseif prev_rail_right ~= nil then
            prev_rail = prev_rail_right
         end
         if check_rail.direction == dirs.north and next_rail == nil then
            dir = dirs.north
         elseif check_rail.direction == dirs.north and prev_rail == nil then
            dir = dirs.south
         elseif check_rail.direction == dirs.northeast and next_rail == nil then
            dir = dirs.northwest
         elseif check_rail.direction == dirs.northeast and prev_rail == nil then
            dir = dirs.southeast
         elseif check_rail.direction == dirs.east and next_rail == nil then
            dir = dirs.east
         elseif check_rail.direction == dirs.east and prev_rail == nil then
            dir = dirs.west
         elseif check_rail.direction == dirs.southeast and next_rail == nil then
            dir = dirs.northeast
         elseif check_rail.direction == dirs.southeast and prev_rail == nil then
            dir = dirs.southwest
         elseif check_rail.direction == dirs.south and next_rail == nil then
            dir = dirs.south
         elseif check_rail.direction == dirs.south and prev_rail == nil then
            dir = dirs.north
         elseif check_rail.direction == dirs.southwest and next_rail == nil then
            dir = dirs.southeast
         elseif check_rail.direction == dirs.southwest and prev_rail == nil then
            dir = dirs.northwest
         elseif check_rail.direction == dirs.west and next_rail == nil then
            dir = dirs.west
         elseif check_rail.direction == dirs.west and prev_rail == nil then
            dir = dirs.east
         elseif check_rail.direction == dirs.northwest and next_rail == nil then
            dir = dirs.southwest
         elseif check_rail.direction == dirs.northwest and prev_rail == nil then
            dir = dirs.northeast
         else
            --This line should not be reachable
            is_end_rail = false
            comment = "Rail direction error."
            return is_end_rail, -3, comment
         end
      elseif check_rail.name == "curved-rail" then 
         local next_rail,r_dir_back,c_dir_back = check_rail.get_connected_rail{rail_direction = defines.rail_direction.front,  
               rail_connection_direction = defines.rail_connection_direction.straight}
         local prev_rail,r_dir_back,c_dir_back = check_rail.get_connected_rail{rail_direction = defines.rail_direction.back,   
               rail_connection_direction = defines.rail_connection_direction.straight}
         if check_rail.direction == dirs.north and next_rail == nil then
            dir = dirs.south
         elseif check_rail.direction == dirs.north and prev_rail == nil then
            dir = dirs.northwest
         elseif check_rail.direction == dirs.northeast and next_rail == nil then
            dir = dirs.south
         elseif check_rail.direction == dirs.northeast and prev_rail == nil then
            dir = dirs.northeast
         elseif check_rail.direction == dirs.east and next_rail == nil then
            dir = dirs.west
         elseif check_rail.direction == dirs.east and prev_rail == nil then
            dir = dirs.northeast
         elseif check_rail.direction == dirs.southeast and next_rail == nil then
            dir = dirs.west
         elseif check_rail.direction == dirs.southeast and prev_rail == nil then
            dir = dirs.southeast
         elseif check_rail.direction == dirs.south and next_rail == nil then
            dir = dirs.north
         elseif check_rail.direction == dirs.south and prev_rail == nil then
            dir = dirs.southeast
         elseif check_rail.direction == dirs.southwest and next_rail == nil then
            dir = dirs.north
         elseif check_rail.direction == dirs.southwest and prev_rail == nil then
            dir = dirs.southwest
         elseif check_rail.direction == dirs.west and next_rail == nil then
            dir = dirs.east
         elseif check_rail.direction == dirs.west and prev_rail == nil then
            dir = dirs.southwest
         elseif check_rail.direction == dirs.northwest and next_rail == nil then
            dir = dirs.east
         elseif check_rail.direction == dirs.northwest and prev_rail == nil then
            dir = dirs.northwest
         else
            --This line should not be reachable
            is_end_rail = false
            comment = "Rail direction error."
            return is_end_rail, -3, comment
         end
      end
   else
      --Not the end rail
      is_end_rail = false
      comment = "This rail is not the end rail."
      return is_end_rail, -4, comment
   end
   
   return is_end_rail, dir, comment
end

--Look up and translate the signal state.
function fa_rails.get_signal_state_info(signal)
   local state_id = 0
   local state_lookup = nil
   local state_name = ""
   local result = ""
   if signal.name == "rail-signal" then
      state_id = signal.signal_state
	  state_lookup = fa_utils.into_lookup(defines.signal_state)
	  state_name = state_lookup[state_id]
	  result = state_name
   elseif signal.name == "rail-chain-signal" then 
      state_id = signal.chain_signal_state
	  state_lookup = fa_utils.into_lookup(defines.chain_signal_state)
	  state_name = state_lookup[state_id]
	  result = state_name
	  if state_name == "none_open" then result = "closed" end
   end
   return result
end

--Returns the rail at the end of an input rail's segment. If the input rail is already one end of the segment then it returns the other end. NOT TESTED
function fa_rails.get_rail_segment_other_end(rail)
   local end_rail_1, end_dir_1 = rail.get_rail_segment_end(defines.rail_direction.front) --Cannot be nil
   local end_rail_2, end_dir_2 = rail.get_rail_segment_end(defines.rail_direction.back) --Cannot be nil
   
   if rail.unit_number == end_rail_1.unit_number and rail.unit_number ~= end_rail_2.unit_number then
      return end_rail_2
   elseif rail.unit_number ~= end_rail_1.unit_number and rail.unit_number == end_rail_2.unit_number then
      return end_rail_1
   else
      --The other end is either both options or neither, so return any.
      return end_rail_1
   end
end

--For a rail at the end of its segment, returns the neighboring rail segment's end rail. Respects dir in terms of left/right/straight if it is given, else returns the first found option.
function fa_rails.get_neighbor_rail_segment_end(rail, con_dir_in)
   local dir = con_dir_in or nil
   local requested_neighbor_rail_1 = nil
   local requested_neighbor_rail_2 = nil
   local neighbor_rail,r_dir_back,c_dir_back = nil, nil, nil
   
   if dir ~= nil then
      --Check requested neighbor
      requested_neighbor_rail_1, req_dir_1, req_con_dir_1 = rail.get_connected_rail{ rail_direction = defines.rail_direction.front,rail_connection_direction = dir}
      requested_neighbor_rail_2, req_dir_2, req_con_dir_2 = rail.get_connected_rail{ rail_direction = defines.rail_direction.back ,rail_connection_direction = dir}
      if requested_neighbor_rail_1 ~= nil and not rail.is_rail_in_same_rail_segment_as(requested_neighbor_rail_1) then
         return requested_neighbor_rail_1, req_dir_1, req_con_dir_1
      elseif requested_neighbor_rail_2 ~= nil and not rail.is_rail_in_same_rail_segment_as(requested_neighbor_rail_2) then
         return requested_neighbor_rail_2, req_dir_2, req_con_dir_2
      else
         return nil, nil, nil
      end
   else    
      --Try all 6 options until you get any
      neighbor_rail,r_dir_back,c_dir_back = rail.get_connected_rail{rail_direction = defines.rail_direction.front,  rail_connection_direction = defines.rail_connection_direction.straight}
      if neighbor_rail ~= nil and not neighbor_rail.is_rail_in_same_rail_segment_as(rail) then
         return neighbor_rail,r_dir_back,c_dir_back
      end
      
      neighbor_rail,r_dir_back,c_dir_back = rail.get_connected_rail{rail_direction = defines.rail_direction.back,   rail_connection_direction = defines.rail_connection_direction.straight}
      if neighbor_rail ~= nil and not neighbor_rail.is_rail_in_same_rail_segment_as(rail) then
         return neighbor_rail,r_dir_back,c_dir_back
      end
      
      neighbor_rail,r_dir_back,c_dir_back = rail.get_connected_rail{ rail_direction = defines.rail_direction.front,rail_connection_direction = defines.rail_connection_direction.left}
      if neighbor_rail ~= nil and not neighbor_rail.is_rail_in_same_rail_segment_as(rail) then
         return neighbor_rail,r_dir_back,c_dir_back
      end
      
      neighbor_rail,r_dir_back,c_dir_back = rail.get_connected_rail{rail_direction = defines.rail_direction.front,rail_connection_direction = defines.rail_connection_direction.right}
      if neighbor_rail ~= nil and not neighbor_rail.is_rail_in_same_rail_segment_as(rail) then
         return neighbor_rail,r_dir_back,c_dir_back
      end
      
      neighbor_rail,r_dir_back,c_dir_back = rail.get_connected_rail{ rail_direction = defines.rail_direction.back,rail_connection_direction = defines.rail_connection_direction.left}
      if neighbor_rail ~= nil and not neighbor_rail.is_rail_in_same_rail_segment_as(rail) then
         return neighbor_rail,r_dir_back,c_dir_back
      end
      
      neighbor_rail,r_dir_back,c_dir_back = rail.get_connected_rail{rail_direction = defines.rail_direction.back,rail_connection_direction = defines.rail_connection_direction.right}
      if neighbor_rail ~= nil and not neighbor_rail.is_rail_in_same_rail_segment_as(rail) then
         return neighbor_rail,r_dir_back,c_dir_back
      end
      
      return nil, nil, nil
   end
end

--Reads all rail segment entities around a rail.
--Result 1: A rail or chain signal creates a new segment and is at the end of one of the two segments.
--Result 2: A train creates a new segment and is at the end of one of the two segments. It can be reported twice for FW1 and BACK2 or for FW2 and BACK1.
function fa_rails.read_all_rail_segment_entities(pindex, rail)
   local message = ""
   local ent_f1 = rail.get_rail_segment_entity(defines.rail_direction.front, true)
   local ent_f2 = rail.get_rail_segment_entity(defines.rail_direction.front, false)
   local ent_b1 = rail.get_rail_segment_entity(defines.rail_direction.back, true)  
   local ent_b2 = rail.get_rail_segment_entity(defines.rail_direction.back, false) 
   
   if ent_f1 == nil then
      message = message .. "forward 1 is nil, "
   elseif ent_f1.name == "train-stop" then
      message = message .. "forward 1 is train stop "               .. ent_f1.backer_name .. ", "
   elseif ent_f1.name == "rail-signal" then 
      message = message .. "forward 1 is rails signal with signal " .. fa_rails.get_signal_state_info(ent_f1) .. ", "
   elseif ent_f1.name == "rail-chain-signal" then 
      message = message .. "forward 1 is chain signal with signal " .. fa_rails.get_signal_state_info(ent_f1) .. ", "
   else
      message = message .. "forward 1 is else, "                    .. ent_f1.name .. ", "
   end
   
   if ent_f2 == nil then
      message = message .. "forward 2 is nil, "
   elseif ent_f2.name == "train-stop" then
      message = message .. "forward 2 is train stop "               .. ent_f2.backer_name .. ", "
   elseif ent_f2.name == "rail-signal" then 
      message = message .. "forward 2 is rails signal with signal " .. fa_rails.get_signal_state_info(ent_f2) .. ", "
   elseif ent_f2.name == "rail-chain-signal" then 
      message = message .. "forward 2 is chain signal with signal " .. fa_rails.get_signal_state_info(ent_f2) .. ", "
   else
      message = message .. "forward 2 is else, "                    .. ent_f2.name .. ", "
   end
   
   if ent_b1 == nil then
      message = message .. "back 1 is nil, "
   elseif ent_b1.name == "train-stop" then
      message = message .. "back 1 is train stop "               .. ent_b1.backer_name .. ", "
   elseif ent_b1.name == "rail-signal" then 
      message = message .. "back 1 is rails signal with signal " .. fa_rails.get_signal_state_info(ent_b1) .. ", "
   elseif ent_b1.name == "rail-chain-signal" then 
      message = message .. "back 1 is chain signal with signal " .. fa_rails.get_signal_state_info(ent_b1) .. ", "
   else
      message = message .. "back 1 is else, "                    .. ent_b1.name .. ", "
   end
   
   if ent_b2 == nil then
      message = message .. "back 2 is nil, "
   elseif ent_b2.name == "train-stop" then
      message = message .. "back 2 is train stop "               .. ent_b2.backer_name .. ", "
   elseif ent_b2.name == "rail-signal" then 
      message = message .. "back 2 is rails signal with signal " .. fa_rails.get_signal_state_info(ent_b2) .. ", "
   elseif ent_b2.name == "rail-chain-signal" then 
      message = message .. "back 2 is chain signal with signal " .. fa_rails.get_signal_state_info(ent_b2) .. ", "
   else
      message = message .. "back 2 is else, "                    .. ent_b2.name .. ", "
   end
   
   printout(message,pindex)
   return
end

--Gets opposite rail direction
function fa_rails.get_opposite_rail_direction(dir)
   if dir == defines.rail_direction.front then
      return defines.rail_direction.back
   else
      return defines.rail_direction.front
   end
end

--Return what is ahead at the end of this rail's segment in this given direction.
--Return the entity, a label, an extra value sometimes, and whether the entity faces the forward direction
function fa_rails.identify_rail_segment_end_object(rail, dir_ahead, accept_only_forward, prefer_back)
   local result_entity = nil
   local result_entity_label = ""
   local result_extra = nil
   local result_is_forward = nil
   
   if rail == nil or rail.valid == false then
      --Error
      result_entity = nil
      result_entity_label = "missing rail"
      return result_entity, result_entity_label, result_extra, result_is_forward
   end
   
   --Correction: Flip the correct direction ahead for mismatching diagonal rails
   if rail.name == "straight-rail" and (rail.direction == dirs.southwest or rail.direction == dirs.northwest) 
      or rail.name == "curved-rail" and (rail.direction == dirs.north or rail.direction == dirs.northeast or rail.direction == dirs.east or rail.direction == dirs.southeast) then
      dir_ahead = fa_rails.get_opposite_rail_direction(dir_ahead)
   end
   
   local segment_last_rail = rail.get_rail_segment_end(dir_ahead)
   local entity_ahead = nil
   local entity_ahead_forward = rail.get_rail_segment_entity(dir_ahead,false)
   local entity_ahead_reverse = rail.get_rail_segment_entity(dir_ahead,true)
   
   local segment_last_is_end_rail, end_rail_dir, comment = fa_rails.check_end_rail(segment_last_rail, pindex)
   local segment_last_neighbor_count = fa_rails.count_rail_connections(segment_last_rail)
   
   if entity_ahead_forward ~= nil then
      entity_ahead = entity_ahead_forward
      result_is_forward = true
   elseif entity_ahead_reverse ~= nil and accept_only_forward == false then
      entity_ahead = entity_ahead_reverse
      result_is_forward = false
   end
   
   if prefer_back == true and entity_ahead_reverse ~= nil and accept_only_forward == false then 
      entity_ahead = entity_ahead_reverse
      result_is_forward = false
   end
   
   --When no entity ahead, check if the segment end is an end rail or fork rail?
   if entity_ahead == nil then
      if segment_last_is_end_rail then
         --End rail
         result_entity = segment_last_rail
         result_entity_label = "end rail"
         result_extra = end_rail_dir
         return result_entity, result_entity_label, result_extra, result_is_forward
      elseif segment_last_neighbor_count > 2 then
         --Junction rail
         result_entity = segment_last_rail
         result_entity_label = "fork split"
         result_extra = rail --A rail from the segment "entering" the junction
         return result_entity, result_entity_label, result_extra, result_is_forward
      else
         --The neighbor of the segment end rail is either a fork or an end rail or has an entity instead
		 neighbor_rail, neighbor_r_dir, neighbor_c_dir = fa_rails.get_neighbor_rail_segment_end(segment_last_rail, nil)
		 if neighbor_rail == nil then
		    --This must be a closed loop?
			result_entity = nil
            result_entity_label = "loop" 
            result_extra = nil
			return result_entity, result_entity_label, result_extra, result_is_forward
		 elseif fa_rails.count_rail_connections(neighbor_rail) > 2 then
		    --The neighbor is a forking rail
			result_entity = neighbor_rail
            result_entity_label = "fork merge" 
            result_extra = nil
			return result_entity, result_entity_label, result_extra, result_is_forward
		 elseif fa_rails.count_rail_connections(neighbor_rail) == 1 then
		    --The neighbor is an end rail
			local neighbor_is_end_rail, end_rail_dir, comment = fa_rails.check_end_rail(neighbor_rail, pindex)
			result_entity = neighbor_rail
            result_entity_label = "neighbor end" 
            result_extra = end_rail_dir
			return result_entity, result_entity_label, result_extra, result_is_forward
		 else
		    --The neighbor rail should have an entity?
            result_entity = segment_last_rail
            result_entity_label = "other rail" 
            result_extra = nil
            return result_entity, result_entity_label, result_extra, result_is_forward
		 end
      end
   --When entity ahead, check its type
   else
      if entity_ahead.name == "rail-signal" then
         result_entity = entity_ahead
         result_entity_label = "rail signal"
         result_extra = fa_rails.get_signal_state_info(entity_ahead)
         return result_entity, result_entity_label, result_extra, result_is_forward
      elseif entity_ahead.name == "rail-chain-signal" then
         result_entity = entity_ahead
         result_entity_label = "chain signal"
         result_extra = fa_rails.get_signal_state_info(entity_ahead)
         return result_entity, result_entity_label, result_extra, result_is_forward
      elseif entity_ahead.name == "train-stop" then
         result_entity = entity_ahead
         result_entity_label = "train stop"
         result_extra = entity_ahead.backer_name
         return result_entity, result_entity_label, result_extra, result_is_forward
      else
         --This is NOT expected.
         result_entity = entity_ahead
         result_entity_label = "other entity"
         result_extra = "Unidentified " .. entity_ahead.name
         return result_entity, result_entity_label, result_extra, result_is_forward
      end
   end
end

--Reads out the nearest railway object ahead with relevant details. Skips to the next segment if needed. 
--The output could be an end rail, junction rail, rail signal, chain signal, or train stop. 
function fa_rails.get_next_rail_entity_ahead(origin_rail, dir_ahead, only_this_segment)
   local next_entity, next_entity_label, result_extra, next_is_forward = fa_rails.identify_rail_segment_end_object(origin_rail, dir_ahead, false, false)
   local iteration_count = 1
   local segment_end_ahead, dir_se = origin_rail.get_rail_segment_end(dir_ahead)
   local prev_rail = segment_end_ahead
   local current_rail = origin_rail
   local neighbor_r_dir = dir_ahead
   local neighbor_c_dir = nil
   
   --First correction for the train stop exception
   if next_entity_label == "train stop" and next_is_forward == false then
      next_entity, next_entity_label, result_extra, next_is_forward = fa_rails.identify_rail_segment_end_object(current_rail, neighbor_r_dir, true, false)
   end
   
   --Skip all "other rail" cases
   while not only_this_segment and next_entity_label == "other rail" and iteration_count < 100 do 
      if iteration_count % 2 == 1 then
         --Switch to neighboring segment
         current_rail, neighbor_r_dir, neighbor_c_dir = fa_rails.get_neighbor_rail_segment_end(prev_rail, nil)
         prev_rail = current_rail
         next_entity, next_entity_label, result_extra, next_is_forward = fa_rails.identify_rail_segment_end_object(current_rail, neighbor_r_dir, false, true)
         --Correction for the train stop exception
         if next_entity_label == "train stop" and next_is_forward == false then
            next_entity, next_entity_label, result_extra, next_is_forward = fa_rails.identify_rail_segment_end_object(current_rail, neighbor_r_dir, true, true)
         end
         --Correction for flipped direction
         if next_is_forward ~= nil then
            next_is_forward = not next_is_forward
         end
         iteration_count = iteration_count + 1
      else
         --Check other end of the segment. NOTE: Never got more than 2 iterations in tests so far...
         neighbor_r_dir = fa_rails.get_opposite_rail_direction(neighbor_r_dir)
         next_entity, next_entity_label, result_extra, next_is_forward = fa_rails.identify_rail_segment_end_object(current_rail, neighbor_r_dir, false, false)
         --Correction for the train stop exception
         if next_entity_label == "train stop" and next_is_forward == false then
            next_entity, next_entity_label, result_extra, next_is_forward = fa_rails.identify_rail_segment_end_object(current_rail, neighbor_r_dir, true, false)
         end
         iteration_count = iteration_count + 1
      end
   end
      
   return next_entity, next_entity_label, result_extra, next_is_forward, iteration_count
end

--Takes all the output from the get_next_rail_entity_ahead and adds extra info before reading them out. Does NOT detect trains.
function fa_rails.rail_read_next_rail_entity_ahead(pindex, rail, is_forward)
   local message = "Up this rail, "
   local origin_rail = rail
   local dir_ahead = defines.rail_direction.front
   if not is_forward then
      dir_ahead = defines.rail_direction.back
	  message = "Down this rail, "
   end
   local next_entity, next_entity_label, result_extra, next_is_forward, iteration_count = fa_rails.get_next_rail_entity_ahead(origin_rail, dir_ahead, false)
   if next_entity == nil then
      printout("Analysis error. This rail might be looping.",pindex)
      return
   end
   local distance = math.floor(util.distance(origin_rail.position, next_entity.position))
      
   --Test message
   --message = message .. iteration_count .. " iterations, "
   
   --Maybe check for trains here, but there is no point because the checks use signal blocks...
   --local trains_in_origin_block = origin_rail.trains_in_block
   --local trains_in_current_block = current_rail.trains_in_block
   
   --Report opposite direction entities.
   if next_is_forward == false and (next_entity_label == "train stop" or next_entity_label == "rail signal" or next_entity_label == "chain signal") then
      message = message .. " Opposite direction's "
   end
   
   --Add more info depending on entity label
   if next_entity_label == "end rail" then
      message = message .. next_entity_label
      
   elseif next_entity_label == "fork split" then
      local entering_segment_rail = result_extra  
      message = message .. "rail fork splitting "
      message = message .. fa_rails.list_rail_fork_directions(next_entity)
   
   elseif next_entity_label == "fork merge" then
      local entering_segment_rail = result_extra  
      message = message .. "rail fork merging "
	  
   elseif next_entity_label == "neighbor end" then
      local entering_segment_rail = result_extra  
      message = message .. "end rail "
	  
   elseif next_entity_label == "rail signal" then
      message = message .. "rail signal with state " .. fa_rails.get_signal_state_info(next_entity) .. " "
      
   elseif next_entity_label == "chain signal" then
      message = message .. "chain signal with state " .. fa_rails.get_signal_state_info(next_entity) .. " "
      
   elseif next_entity_label == "train stop" then
      local stop_name = next_entity.backer_name
      --Add more specific distance info
      if math.abs(distance) > 25 or next_is_forward == false then
         message = message .. "Train stop " .. stop_name .. ", in " .. distance .. " meters, "
      else
         distance = util.distance(origin_rail.position, next_entity.position) - 2.5
         if math.abs(distance) <= 0.2 then
            message = " Aligned with train stop " .. stop_name
         elseif distance > 0.2 then
            message = math.floor(distance * 10) / 10 .. " meters away from train stop " .. stop_name .. ". " 
         elseif distance < 0.2 then
            message = math.floor((-distance) * 10) / 10 .. " meters past train stop " .. stop_name .. ". " 
         end
      end
   
   elseif next_entity_label == "other rail" then
      message = message .. "unspecified entity"
      
   elseif next_entity_label == "other entity" then
      message = message .. next_entity.name
   end
   
   --Add general distance info
   if next_entity_label ~= "train stop" then
      message = message .. " in " .. distance .. " meters, "
      if next_entity_label == "end rail" then
         message = message .. " facing " .. fa_utils.direction_lookup(result_extra)
      end
   end
   printout(message,pindex)
   --Draw circles for visual debugging
   rendering.draw_circle{color = {0, 1, 0},radius = 1,width = 10,target = next_entity,surface = next_entity.surface,time_to_live = 100}
end

--WIP. laterdo here: Rail analyzer menu where you will use arrow keys to go forward/back and left/right along a rail.
function fa_rails.run_rail_analyzer_menu(pindex, origin_rail,is_called_from_train)
   return
end

--Builds a 45 degree rail turn to the right from a horizontal or vertical end rail that is the anchor rail. 
function fa_rail_builder.build_rail_turn_right_45_degrees(anchor_rail, pindex)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   local anchor_dir = anchor_rail.direction
   
   --1. Firstly, check if the player has enough rails to place this (3 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count >= 3) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail") < 3 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 3 rails in your inventory to build this turn.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --2. Secondly, verify the end rail and find its direction
   is_end_rail, dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if not is_end_rail then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(build_comment, pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   pos = anchor_rail.position
   
   --3. Clear trees and rocks in the build area, can be tuned later...
   -- if dir == dirs.north or dir == dirs.northeast then
      -- build_area = {{pos.x-9, pos.y+9},{pos.x+16,pos.y-16}}
   -- elseif dir == dirs.east or dir == dirs.southeast then
      -- build_area = {{pos.x-9, pos.y-9},{pos.x+16,pos.y+16}}
   -- elseif dir == dirs.south or dir == dirs.southwest then
      -- build_area = {{pos.x+9, pos.y-9},{pos.x-16,pos.y+16}}
   -- elseif dir == dirs.west or dir == dirs.northwest then
      -- build_area = {{pos.x+9, pos.y+9},{pos.x-16,pos.y-16}}
   -- end 
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,12, pindex)
   
   --4. Check if every object can be placed
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+2, pos.y-4}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+2}, direction = dirs.southeast, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+0, pos.y+6}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+0}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.northwest then
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.west, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+2, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y-2}, direction = dirs.west, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.southeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.east, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-2, pos.y+0}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+4}, direction = dirs.east, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.northeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.north, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y+6}, direction = dirs.north, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.southwest then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.south, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y-4}, direction = dirs.south, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   end
  
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5. Build the rail entities to create the turn
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail", position = {pos.x+2, pos.y-4}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+2}, direction = dirs.southeast, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail", position = {pos.x+0, pos.y+6}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+0}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.northwest then
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.west, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then
         surf.create_entity{name = "straight-rail", position = {pos.x+2, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y-2}, direction = dirs.west, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.southeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.east, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-2, pos.y+0}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+4}, direction = dirs.east, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.northeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.north, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y+6}, direction = dirs.north, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.southwest then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.south, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y-4}, direction = dirs.south, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   end
   
   
   --6 Remove rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 2
   if (dir == dirs.northeast and anchor_dir == dirs.southeast) or (dir == dirs.southwest and anchor_dir == dirs.northwest) or (dir == dirs.southeast and anchor_dir == dirs.southwest) or (dir == dirs.northwest and anchor_dir == dirs.northeast) then
      game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 1
   end
   game.get_player(pindex).clear_cursor()
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   printout("Rail turn built 45 degrees right, " .. build_comment, pindex)
   return
   
end


--Builds a 90 degree rail turn to the right from a horizontal or vertical end rail that is the anchor rail. 
function fa_rail_builder.build_rail_turn_right_90_degrees(anchor_rail, pindex)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   
   --1. Firstly, check if the player has enough rails to place this (10 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count >= 10) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail") < 10 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 10 rails in your inventory to build this turn.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --2. Secondly, verify the end rail and find its direction
   is_end_rail, dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if not is_end_rail then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(build_comment, pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   pos = anchor_rail.position
   if dir == dirs.northeast or dir == dirs.southeast or dir == dirs.southwest or dir == dirs.northwest then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("This structure is for horizontal or vertical end rails only.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --3. Clear trees and rocks in the build area
   -- if dir == dirs.north then
      -- build_area = {{pos.x-2, pos.y+2},{pos.x+16,pos.y-16}}
   -- elseif dir == dirs.east then
      -- build_area = {{pos.x-2, pos.y-2},{pos.x+16,pos.y+16}}
   -- elseif dir == dirs.south then
      -- build_area = {{pos.x+2, pos.y-2},{pos.x-16,pos.y+16}}
   -- elseif dir == dirs.west then
      -- build_area = {{pos.x+2, pos.y+2},{pos.x-16,pos.y-16}}
   -- end 
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,18, pindex)
   
   --4. Check if every object can be placed
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+2, pos.y-4}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+8, pos.y-10}, direction = dirs.west, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+12, pos.y-12}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+2}, direction = dirs.southeast, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+12, pos.y+8}, direction = dirs.north, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+12, pos.y+12}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+0, pos.y+6}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-6, pos.y+12}, direction = dirs.east, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-12, pos.y+12}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+0}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-10, pos.y-6}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-12, pos.y-12}, direction = dirs.north, force = game.forces.player}
   end
  
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5. Build the five rail entities to create the turn
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail", position = {pos.x+2, pos.y-4}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x+8, pos.y-10}, direction = dirs.west, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+12, pos.y-12}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+2}, direction = dirs.southeast, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x+12, pos.y+8}, direction = dirs.north, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+12, pos.y+12}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail", position = {pos.x+0, pos.y+6}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x-6, pos.y+12}, direction = dirs.east, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x-12, pos.y+12}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+0}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x-10, pos.y-6}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-12, pos.y-12}, direction = dirs.north, force = game.forces.player}
   end
   
   --6 Remove 10 rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 10
   game.get_player(pindex).clear_cursor()
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   printout("Rail turn built 90 degrees right, " .. build_comment, pindex)
   return
   
end


--Builds a 45 degree rail turn to the left from a horizontal or vertical end rail that is the anchor rail. 
function fa_rail_builder.build_rail_turn_left_45_degrees(anchor_rail, pindex)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   local anchor_dir = anchor_rail.direction
   
   --1. Firstly, check if the player has enough rails to place this (3 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count >= 3) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail") < 3 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 3 rails in your inventory to build this turn.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --2. Secondly, verify the end rail and find its direction
   is_end_rail, dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if not is_end_rail then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(build_comment, pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   pos = anchor_rail.position
   
   --3. Clear trees and rocks in the build area, can be tuned later...
   -- if dir == dirs.north or dir == dirs.northeast then
      -- build_area = {{pos.x+9, pos.y+9},{pos.x-16,pos.y-16}}
   -- elseif dir == dirs.east or dir == dirs.southeast then
      -- build_area = {{pos.x-9, pos.y+9},{pos.x+16,pos.y-16}}
   -- elseif dir == dirs.south or dir == dirs.southwest then
      -- build_area = {{pos.x-9, pos.y-9},{pos.x+16,pos.y+16}}
   -- elseif dir == dirs.west or dir == dirs.northwest then
      -- build_area = {{pos.x+9, pos.y-9},{pos.x-16,pos.y+16}}
   -- end 
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,12, pindex)
   
   --4. Check if every object can be placed
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+0, pos.y-4}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+0}, direction = dirs.east, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+2, pos.y+6}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+2}, direction = dirs.west, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.southeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+0, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.northwest then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y+6}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.southwest then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+2, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.northeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-2, pos.y-0}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   end
  
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5. Build the rail entities to create the turn
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail", position = {pos.x+0, pos.y-4}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+0}, direction = dirs.east, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail", position = {pos.x+2, pos.y+6}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+2}, direction = dirs.west, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.southeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x+0, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.northwest then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y+6}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.southwest then--2
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         surf.create_entity{name = "straight-rail", position = {pos.x+2, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.northeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-2, pos.y-0}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   end
   
   
   --6 Remove rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 2
   if (dir == dirs.northeast and anchor_dir == dirs.northwest) or (dir == dirs.southwest and anchor_dir == dirs.southeast) or (dir == dirs.southeast and anchor_dir == dirs.northeast) or (dir == dirs.northwest and anchor_dir == dirs.southwest) then
      game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 1
   end
   game.get_player(pindex).clear_cursor()
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   printout("Rail turn built 45 degrees left, " .. build_comment, pindex)
   return
   
end


--Builds a 90 degree rail turn to the left from a horizontal or vertical end rail that is the anchor rail. 
function fa_rail_builder.build_rail_turn_left_90_degrees(anchor_rail, pindex)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   
   --1. Firstly, check if the player has enough rails to place this (10 units)
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count > 10) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail") < 10 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 10 rails in your inventory to build this turn.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --2. Secondly, verify the end rail and find its direction
   is_end_rail, dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if not is_end_rail then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(build_comment, pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   pos = anchor_rail.position
   if dir == dirs.northeast or dir == dirs.southeast or dir == dirs.southwest or dir == dirs.northwest then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("This structure is for horizontal or vertical end rails only.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --3. Clear trees and rocks in the build area
   -- if dir == dirs.north then
      -- build_area = {{pos.x+2, pos.y+2},{pos.x-16,pos.y-16}}
   -- elseif dir == dirs.east then
      -- build_area = {{pos.x+2, pos.y+2},{pos.x+16,pos.y-16}}
   -- elseif dir == dirs.south then
      -- build_area = {{pos.x+2, pos.y+2},{pos.x+16,pos.y+16}}
   -- elseif dir == dirs.west then
      -- build_area = {{pos.x+2, pos.y+2},{pos.x-16,pos.y+16}}
   -- end 
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,18, pindex)
   
   --4. Check if every object can be placed
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+0, pos.y-4}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-6, pos.y-10}, direction = dirs.southeast, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-12, pos.y-12}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+0}, direction = dirs.east, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+12, pos.y-6}, direction = dirs.southwest, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+12, pos.y-12}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+2, pos.y+6}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+8, pos.y+12}, direction = dirs.northwest, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+12, pos.y+12}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+2}, direction = dirs.west, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-10, pos.y+8}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-12, pos.y+12}, direction = dirs.north, force = game.forces.player}
   end
  
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5. Build the five rail entities to create the turn
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail", position = {pos.x+0, pos.y-4}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x-6, pos.y-10}, direction = dirs.southeast, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x-12, pos.y-12}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+0}, direction = dirs.east, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x+12, pos.y-6}, direction = dirs.southwest, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+12, pos.y-12}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail", position = {pos.x+2, pos.y+6}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x+8, pos.y+12}, direction = dirs.northwest, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+12, pos.y+12}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+2}, direction = dirs.west, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail", position = {pos.x-10, pos.y+8}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-12, pos.y+12}, direction = dirs.north, force = game.forces.player}
   end
   
   --6 Remove 10 rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 10
   game.get_player(pindex).clear_cursor()
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   printout("Rail turn built 90 degrees left, " .. build_comment, pindex)
   return
end


--Builds a fork at the end rail with exits 45 degrees left, and 45 degrees right, and forward.
function fa_rail_builder.build_fork_at_end_rail(anchor_rail, pindex, include_forward)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   local anchor_dir = anchor_rail.direction
   
   --1. Firstly, check if the player has enough rails to place this (5 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count >= 5) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail") < 5 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 5 rails in your inventory to build this turn.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --2. Secondly, verify the end rail and find its direction
   is_end_rail, dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if not is_end_rail then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(build_comment, pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   pos = anchor_rail.position
   
   --3. Clear trees and rocks in the build area, can be tuned later...
   -- if dir == dirs.north or dir == dirs.northeast then
      -- build_area = {{pos.x+9, pos.y+9},{pos.x-16,pos.y-16}}
   -- elseif dir == dirs.east or dir == dirs.southeast then
      -- build_area = {{pos.x-9, pos.y+9},{pos.x+16,pos.y-16}}
   -- elseif dir == dirs.south or dir == dirs.southwest then
      -- build_area = {{pos.x-9, pos.y-9},{pos.x+16,pos.y+16}}
   -- elseif dir == dirs.west or dir == dirs.northwest then
      -- build_area = {{pos.x+9, pos.y-9},{pos.x-16,pos.y+16}}
   -- end 
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,12, pindex)
   
   --4A. Check if every object can be placed (LEFT)
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+0, pos.y-4}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+0}, direction = dirs.east, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+2, pos.y+6}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+2}, direction = dirs.west, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.southeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+0, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.northwest then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y+6}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.southwest then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+2, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.northeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-2, pos.y-0}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   end
   
   --4B. Check if every object can be placed (RIGHT)
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+2, pos.y-4}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y+2}, direction = dirs.southeast, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+0, pos.y+6}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+0}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.northwest then
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.west, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+2, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+6, pos.y-2}, direction = dirs.west, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.southeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.east, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-2, pos.y+0}, direction = dirs.southeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-4, pos.y+4}, direction = dirs.east, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.northeast then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.north, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northeast, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x+4, pos.y+6}, direction = dirs.north, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.southwest then--2
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.south, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail", position = {pos.x-2, pos.y-4}, direction = dirs.south, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   end
   
   --4C. Check if can append forward  
   if include_forward then
      if dir == dirs.north then 
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y-2}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y-4}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y-6}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y-8}, direction = dir, force = game.forces.player}
      elseif dir == dirs.east then 
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+2, pos.y-0}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+4, pos.y-0}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+6, pos.y-0}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+8, pos.y-0}, direction = dir, force = game.forces.player}
      elseif dir == dirs.south then
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+4}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+6}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-0, pos.y+8}, direction = dir, force = game.forces.player}
      elseif dir == dirs.west then
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-2, pos.y-0}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-4, pos.y-0}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-6, pos.y-0}, direction = dir, force = game.forces.player}
         can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-8, pos.y-0}, direction = dir, force = game.forces.player}
      else
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("Error: rail placement not defined", pindex)
         game.get_player(pindex).clear_cursor()
         return
      end
   end
  
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5A. Build the rail entities to create the turn (LEFT)
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail", position = {pos.x+0, pos.y-4}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+0}, direction = dirs.east, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail", position = {pos.x+2, pos.y+6}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+2}, direction = dirs.west, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.southeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x+0, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.northwest then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y+6}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.southwest then--2
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         surf.create_entity{name = "straight-rail", position = {pos.x+2, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+4}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.northeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-2, pos.y-0}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   end
   
   --5B. Build the rail entities to create the turn (RIGHT)
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail", position = {pos.x+2, pos.y-4}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-8}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y+2}, direction = dirs.southeast, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y+4}, direction = dirs.northeast, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail", position = {pos.x+0, pos.y+6}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y+8}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+0}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y-4}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northeast then
      if anchor_dir == dirs.northwest then
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y-2}, direction = dirs.west, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y-4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.southeast then
         surf.create_entity{name = "straight-rail", position = {pos.x+2, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+6, pos.y-2}, direction = dirs.west, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y-4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southwest then
      if anchor_dir == dirs.southeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y+4}, direction = dirs.east, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y+4}, direction = dirs.east, force = game.forces.player}
      elseif anchor_dir == dirs.northwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-2, pos.y+0}, direction = dirs.southeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-4, pos.y+4}, direction = dirs.east, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y+4}, direction = dirs.east, force = game.forces.player}
      end
   elseif dir == dirs.southeast then
      if anchor_dir == dirs.northeast then--2
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y+4}, direction = dirs.north, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y+8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.southwest then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dirs.northeast, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x+4, pos.y+6}, direction = dirs.north, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y+10}, direction = dirs.north, force = game.forces.player}
      end
   elseif dir == dirs.northwest then
      if anchor_dir == dirs.southwest then--2
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y-2}, direction = dirs.south, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-8}, direction = dirs.north, force = game.forces.player}
      elseif anchor_dir == dirs.northeast then--3
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y-2}, direction = dirs.southwest, force = game.forces.player}
         surf.create_entity{name = "curved-rail", position = {pos.x-2, pos.y-4}, direction = dirs.south, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-10}, direction = dirs.north, force = game.forces.player}
      end
   end
   
   --5C. Add Forward section
   if include_forward then
      if dir == dirs.north then 
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y-2}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y-4}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y-6}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y-8}, direction = dir, force = game.forces.player}
      elseif dir == dirs.east then 
         surf.create_entity{name = "straight-rail", position = {pos.x+2, pos.y-0}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+4, pos.y-0}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+6, pos.y-0}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x+8, pos.y-0}, direction = dir, force = game.forces.player}
      elseif dir == dirs.south then
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+2}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+4}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+6}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-0, pos.y+8}, direction = dir, force = game.forces.player}
      elseif dir == dirs.west then
         surf.create_entity{name = "straight-rail", position = {pos.x-2, pos.y-0}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-4, pos.y-0}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-6, pos.y-0}, direction = dir, force = game.forces.player}
         surf.create_entity{name = "straight-rail", position = {pos.x-8, pos.y-0}, direction = dir, force = game.forces.player}
      else
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("Error: rail placement not defined", pindex)
         game.get_player(pindex).clear_cursor()
         return
      end
   end
   
   --6 Remove rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 5
   game.get_player(pindex).clear_cursor()
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   local result = "Rail fork built with 2 exits, " .. build_comment
   if include_forward then
      result = "Rail fork built with 3 exits, " .. build_comment
   end
   printout(result,pindex)
   return
   
end

--Builds a starter for a rail bypass junction with 2 rails
function fa_rail_builder.build_rail_bypass_junction(anchor_rail, pindex)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   local anchor_dir = anchor_rail.direction
   
   --1A. Firstly, check if the player has enough rails to place this (20 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count >= 20) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail") < 20 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 20 rails in your inventory to build this.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --1B. Check if the player has enough rail signals to place this (4 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail-chain-signal" and stack.count >= 4) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail-chain-signal") < 4 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 4 rail chain signals in your inventory to build this.", pindex)
         return
      else
         --Good to go.
      end
   end
   
   --2. Secondly, verify the end rail and find its direction
   is_end_rail, dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if not is_end_rail then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(build_comment, pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   pos = anchor_rail.position
   
   --3. Clear trees and rocks in the build area, can be tuned later...
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,21,pindex)
   
   --4A. Check if every object can be placed (LEFT)
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-00, pos.y-04}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y-08}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y-10}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-06, pos.y-12}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+06, pos.y-00}, direction = dirs.east, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y-04}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y-04}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+14, pos.y-06}, direction = dirs.west, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+18, pos.y-08}, direction = dirs.east, force = game.forces.player} 
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+02, pos.y+06}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y+08}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y+10}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+08, pos.y+14}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y+18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-04, pos.y+02}, direction = dirs.west, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y+04}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y+04}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-12, pos.y+08}, direction = dirs.east, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-18, pos.y+08}, direction = dirs.west, force = game.forces.player}
   end
   
   --4B. Check if every object can be placed (RIGHT)
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+02, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y-08}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y-10}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+08, pos.y-12}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+06, pos.y+02}, direction = dirs.southeast, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y+04}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y+04}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+14, pos.y+08}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+18, pos.y+08}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-00, pos.y+06}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y+08}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y+10}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-06, pos.y+14}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y+18}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-04, pos.y-00}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y-04}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-12, pos.y-06}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-18, pos.y-08}, direction = dirs.west, force = game.forces.player}
   end
   
   --4C. Check if every object can be placed (SIGNALS)
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x+03, pos.y-07}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-04, pos.y-07}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y+01}, direction = dirs.west , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y-02}, direction = dirs.east , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x+06, pos.y+03}, direction = dirs.northwest , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+06, pos.y-04}, direction = dirs.northeast , force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x-04, pos.y+06}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+03, pos.y+06}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y-02}, direction = dirs.east , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y+01}, direction = dirs.west , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x-07, pos.y-04}, direction = dirs.southeast , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-07, pos.y+03}, direction = dirs.southwest , force = game.forces.player}
   end
   
   if dir == dirs.northeast or dir == dirs.northwest or dir == dirs.southeast or dir == dirs.southwest then
      can_place_all = false
   end
   
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5A. Build the rail entities to create the turn (LEFT)
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail"  , position = {pos.x-00, pos.y-04}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y-08}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y-10}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-06, pos.y-12}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail"  , position = {pos.x+06, pos.y-00}, direction = dirs.east, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y-04}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y-04}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+14, pos.y-06}, direction = dirs.west, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+18, pos.y-08}, direction = dirs.east, force = game.forces.player} 
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail"  , position = {pos.x+02, pos.y+06}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y+08}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y+10}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+08, pos.y+14}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y+18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail"  , position = {pos.x-04, pos.y+02}, direction = dirs.west, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y+04}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y+04}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-12, pos.y+08}, direction = dirs.east, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-18, pos.y+08}, direction = dirs.west, force = game.forces.player}
   end
   
   --5B. Build the rail entities to create the turn (RIGHT)
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail"  , position = {pos.x+02, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y-08}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y-10}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+08, pos.y-12}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail"  , position = {pos.x+06, pos.y+02}, direction = dirs.southeast, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y+04}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y+04}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+14, pos.y+08}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+18, pos.y+08}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail"  , position = {pos.x-00, pos.y+06}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y+08}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y+10}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-06, pos.y+14}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y+18}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail"  , position = {pos.x-04, pos.y-00}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y-04}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-12, pos.y-06}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-18, pos.y-08}, direction = dirs.west, force = game.forces.player}
   end
   
   --5C. Place rail signals (4)
   if dir == dirs.north then 
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x+03, pos.y-07}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-04, pos.y-07}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y+01}, direction = dirs.west , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y-02}, direction = dirs.east , force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x+06, pos.y+03}, direction = dirs.northwest , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+06, pos.y-04}, direction = dirs.northeast , force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x-04, pos.y+06}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+03, pos.y+06}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y-02}, direction = dirs.east , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y+01}, direction = dirs.west , force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x-07, pos.y-04}, direction = dirs.southeast , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-07, pos.y+03}, direction = dirs.southwest , force = game.forces.player}
   end
   
   --6 Remove rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 20
   game.get_player(pindex).clear_cursor()
   game.get_player(pindex).get_main_inventory().remove({name="rail-chain-signal", count=4})
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   local result = "Rail bypass junction built, " .. build_comment
   printout(result,pindex)
   return
   
end

--Builds a starter for a rail bypass junction with 3 rails ***todo complete and test
function fa_rail_builder.build_rail_bypass_junction_triple(anchor_rail, pindex)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   local anchor_dir = anchor_rail.direction
   
   --1A. Firstly, check if the player has enough rails to place this (25 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count >= 25) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail") < 25 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 25 rails in your inventory to build this.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --1B. Check if the player has enough rail signals to place this (6 units) 
   if not (stack.valid and stack.valid_for_read and stack.name == "rail-chain-signal" and stack.count >= 6) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("rail-chain-signal") < 6 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 6 rail chain signals in your inventory to build this.", pindex)
         return
      else
         --Good to go.
      end
   end
   
   --2. Secondly, verify the end rail and find its direction
   is_end_rail, dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if not is_end_rail then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(build_comment, pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   pos = anchor_rail.position
   
   --3. Clear trees and rocks in the build area, can be tuned later...
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,21,pindex)
   
   --4A. Check if every object can be placed (LEFT)
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-00, pos.y-04}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y-08}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y-10}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-06, pos.y-12}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+06, pos.y-00}, direction = dirs.east, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y-04}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y-04}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+14, pos.y-06}, direction = dirs.west, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+18, pos.y-08}, direction = dirs.east, force = game.forces.player} 
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+02, pos.y+06}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y+08}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y+10}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+08, pos.y+14}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y+18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-04, pos.y+02}, direction = dirs.west, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y+04}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y+04}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-12, pos.y+08}, direction = dirs.east, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-18, pos.y+08}, direction = dirs.west, force = game.forces.player}
   end
   
   --4B. Check if every object can be placed (RIGHT)
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+02, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y-08}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+04, pos.y-10}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+08, pos.y-12}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+06, pos.y+02}, direction = dirs.southeast, force = game.forces.player} 
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y+04}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+10, pos.y+04}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x+14, pos.y+08}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x+18, pos.y+08}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-00, pos.y+06}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y+08}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-04, pos.y+10}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-06, pos.y+14}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y+18}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-04, pos.y-00}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y-04}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-10, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "curved-rail"  , position = {pos.x-12, pos.y-06}, direction = dirs.southeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "straight-rail", position = {pos.x-18, pos.y-08}, direction = dirs.west, force = game.forces.player}
   end
   
   --4C. Check if every object can be placed (MIDDLE) todo*** also be okay with there already being straight rails here 
   if dir == dirs.north then 
      can_place_all = can_place_all and (surf.can_place_entity{name = "straight-rail", position = {pos.x+08, pos.y-18}, direction = dirs.north, force = game.forces.player} or true)
   elseif dir == dirs.east then
      can_place_all = can_place_all and (surf.can_place_entity{name = "straight-rail", position = {pos.x+18, pos.y+08}, direction = dirs.east, force = game.forces.player} or true)
   elseif dir == dirs.south then
      can_place_all = can_place_all and (surf.can_place_entity{name = "straight-rail", position = {pos.x-08, pos.y+18}, direction = dirs.south, force = game.forces.player} or true)
   elseif dir == dirs.west then
      can_place_all = can_place_all and (surf.can_place_entity{name = "straight-rail", position = {pos.x-18, pos.y-08}, direction = dirs.west, force = game.forces.player} or true)
   end
   
   --4D. Check if every object can be placed (SIGNALS) todo ***
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x+03, pos.y-07}, direction = dirs.southwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-04, pos.y-07}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y+01}, direction = dirs.west , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y-02}, direction = dirs.east , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x+06, pos.y+03}, direction = dirs.northwest , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+06, pos.y-04}, direction = dirs.northeast , force = game.forces.player}
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x-04, pos.y+06}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+03, pos.y+06}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y-02}, direction = dirs.east , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y+01}, direction = dirs.west , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal"      , position = {pos.x-07, pos.y-04}, direction = dirs.southeast , force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-07, pos.y+03}, direction = dirs.southwest , force = game.forces.player}
   end
   
   if dir == dirs.northeast or dir == dirs.northwest or dir == dirs.southeast or dir == dirs.southwest then
      can_place_all = false
   end
   
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5A. Build the rail entities to create the turn (LEFT)
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail"  , position = {pos.x-00, pos.y-04}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y-08}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y-10}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-06, pos.y-12}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail"  , position = {pos.x+06, pos.y-00}, direction = dirs.east, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y-04}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y-04}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+14, pos.y-06}, direction = dirs.west, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+18, pos.y-08}, direction = dirs.east, force = game.forces.player} 
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail"  , position = {pos.x+02, pos.y+06}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y+08}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y+10}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+08, pos.y+14}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y+18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail"  , position = {pos.x-04, pos.y+02}, direction = dirs.west, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y+04}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y+04}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-12, pos.y+08}, direction = dirs.east, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-18, pos.y+08}, direction = dirs.west, force = game.forces.player}
   end
   
   --5B. Build the rail entities to create the turn (RIGHT)
   if dir == dirs.north then 
      surf.create_entity{name = "curved-rail"  , position = {pos.x+02, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y-08}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+04, pos.y-10}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+08, pos.y-12}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "curved-rail"  , position = {pos.x+06, pos.y+02}, direction = dirs.southeast, force = game.forces.player} 
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y+04}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+10, pos.y+04}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x+14, pos.y+08}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x+18, pos.y+08}, direction = dirs.east, force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "curved-rail"  , position = {pos.x-00, pos.y+06}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y+08}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-04, pos.y+10}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-06, pos.y+14}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y+18}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "curved-rail"  , position = {pos.x-04, pos.y-00}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y-04}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-10, pos.y-04}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "curved-rail"  , position = {pos.x-12, pos.y-06}, direction = dirs.southeast, force = game.forces.player}
      surf.create_entity{name = "straight-rail", position = {pos.x-18, pos.y-08}, direction = dirs.west, force = game.forces.player}
   end
   
   --5C. Build the rail entities to create the exit (MIDDLE) todo ***
   if dir == dirs.north then 
      surf.create_entity{name = "straight-rail", position = {pos.x+08, pos.y-18}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "straight-rail", position = {pos.x+18, pos.y+08}, direction = dirs.east,  force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "straight-rail", position = {pos.x-08, pos.y+18}, direction = dirs.south, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "straight-rail", position = {pos.x-18, pos.y-08}, direction = dirs.west,  force = game.forces.player}
   end
   
   --5D. Place rail signals (6) todo ***
   if dir == dirs.north then 
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x+03, pos.y-07}, direction = dirs.southwest, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-04, pos.y-07}, direction = dirs.northwest, force = game.forces.player}
   elseif dir == dirs.east then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y+01}, direction = dirs.west , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-01, pos.y-02}, direction = dirs.east , force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x+06, pos.y+03}, direction = dirs.northwest , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+06, pos.y-04}, direction = dirs.northeast , force = game.forces.player}
   elseif dir == dirs.south then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-02, pos.y-00}, direction = dirs.north, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+01, pos.y-00}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x-04, pos.y+06}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+03, pos.y+06}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.west then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y-02}, direction = dirs.east , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-00, pos.y+01}, direction = dirs.west , force = game.forces.player}
      surf.create_entity{name = "rail-signal"      , position = {pos.x-07, pos.y-04}, direction = dirs.southeast , force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-07, pos.y+03}, direction = dirs.southwest , force = game.forces.player}
   end
   
   --6 Remove rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 25
   game.get_player(pindex).clear_cursor()
   game.get_player(pindex).get_main_inventory().remove({name="rail-chain-signal", count=6})
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   game.get_player(pindex).play_sound{path = "entity-build/curved-rail"}
   local result = "Rail bypass junction built with 3 branches, " .. build_comment
   printout(result,pindex)
   return
   
end

--Appends a new straight or diagonal rail to a rail end found near the input position. The cursor needs to be holding rails.
function fa_rails.append_rail(pos, pindex)
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local is_end_rail = false
   local end_found = nil
   local end_dir = nil
   local end_dir_1 = nil
   local end_dir_2 = nil
   local rail_api_dir = nil
   local is_end_rail = nil
   local end_rail_dir = nil
   local comment = ""
   
   --0 Check if there is at least 1 rail in hand, else return
   if not (stack.valid and stack.valid_for_read and stack.name == "rail" and stack.count > 0) then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("You need at least 1 rail in hand.", pindex)
      return
   end
   
   --1 Check the cursor entity. If it is an end rail, use this instead of scanning to extend the rail you want.
   local ent = players[pindex].tile.ents[1]
   is_end_rail, end_rail_dir, comment = fa_rails.check_end_rail(ent,pindex)
   if is_end_rail then
      end_found = ent
      end_rail_1, end_dir_1 = ent.get_rail_segment_end(defines.rail_direction.front)
      end_rail_2, end_dir_2 = ent.get_rail_segment_end(defines.rail_direction.back)
      if ent.unit_number == end_rail_1.unit_number then
         end_dir = end_dir_1
      elseif ent.unit_number == end_rail_2.unit_number then
         end_dir = end_dir_2
      end
   else
      --2 Scan the area around within a X tile radius of pos
      local ents = surf.find_entities_filtered{position = pos, radius = 3, name = "straight-rail"}
      if #ents == 0 then
         ents = surf.find_entities_filtered{position = pos, radius = 3, name = "curved-rail"}
         if #ents == 0 then
            game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            if players[pindex].build_lock == false then
               printout("No rails found nearby.",pindex)
               return
            end
         end
      end

      --3 For the first rail found, check if it is at the end of its segment and if the rail is not within X tiles of pos, try the other end
      for i,rail in ipairs(ents) do
         end_rail_1, end_dir_1 = rail.get_rail_segment_end(defines.rail_direction.front)
         end_rail_2, end_dir_2 = rail.get_rail_segment_end(defines.rail_direction.back)
         if util.distance(pos, end_rail_1.position) < 3 then--is within range
            end_found = end_rail_1
            end_dir = end_dir_1
         elseif util.distance(pos, end_rail_2.position) < 3 then--is within range
            end_found = end_rail_2
            end_dir = end_dir_2
         end
      end   
      if end_found == nil then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         if players[pindex].build_lock == false then
            printout("No end rails found nearby", pindex)
         end
         return
      end
      
      --4 Check if the found segment end is an end rail
      is_end_rail, end_rail_dir, comment = fa_rails.check_end_rail(end_found,pindex)
      if not is_end_rail then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         --printout(comment, pindex)
         printout("No end rails found nearby", pindex)
         return
      end
   end
   
   --5 Confirmed as an end rail. Get its position and find the correct position and direction for the appended rail.
   end_rail_pos = end_found.position
   end_rail_dir = end_found.direction
   append_rail_dir = -1
   append_rail_pos = nil
   rail_api_dir = end_found.direction
   
   --printout(" Rail end found at " .. end_found.position.x .. " , " .. end_found.position.y .. " , facing " .. end_found.direction, pindex)--Checks

   if end_found.name == "straight-rail" then
      if end_rail_dir == dirs.north or end_rail_dir == dirs.south then 
         append_rail_dir = dirs.north
         if end_dir == defines.rail_direction.front then
            append_rail_pos = {end_rail_pos.x+0, end_rail_pos.y-2}
         else
            append_rail_pos = {end_rail_pos.x+0, end_rail_pos.y+2}
         end
         
      elseif end_rail_dir == dirs.east or end_rail_dir == dirs.west then
         append_rail_dir = dirs.east
         if end_dir == defines.rail_direction.front then
            append_rail_pos = {end_rail_pos.x+2, end_rail_pos.y+0}
         else
            append_rail_pos = {end_rail_pos.x-2, end_rail_pos.y-0}
         end
         
      elseif end_rail_dir == dirs.northeast then
         append_rail_dir = dirs.southwest
         if end_dir == defines.rail_direction.front then
            append_rail_pos = {end_rail_pos.x+0, end_rail_pos.y-2}
         else
            append_rail_pos = {end_rail_pos.x+2, end_rail_pos.y+0}
         end
      elseif end_rail_dir == dirs.southwest then
         append_rail_dir = dirs.northeast
         if end_dir == defines.rail_direction.front then
            append_rail_pos = {end_rail_pos.x+0, end_rail_pos.y+2}
         else
            append_rail_pos = {end_rail_pos.x-2, end_rail_pos.y+0}
         end
         
      elseif end_rail_dir == dirs.southeast then
         append_rail_dir = dirs.northwest
         if end_dir == defines.rail_direction.front then
            append_rail_pos = {end_rail_pos.x+2, end_rail_pos.y+0}
         else
            append_rail_pos = {end_rail_pos.x+0, end_rail_pos.y+2}
         end
      elseif end_rail_dir == dirs.northwest then
         append_rail_dir = dirs.southeast
         if end_dir == defines.rail_direction.front then
            append_rail_pos = {end_rail_pos.x-2, end_rail_pos.y+0}
         else
            append_rail_pos = {end_rail_pos.x+0, end_rail_pos.y-2}
         end
      end
      
   elseif end_found.name == "curved-rail" then
      --Make sure to use the reported end direction for curved rails
      is_end_rail, end_rail_dir, comment = fa_rails.check_end_rail(ent,pindex)
      if end_rail_dir == dirs.north then
         if rail_api_dir == dirs.south then
            append_rail_pos = {end_rail_pos.x-2, end_rail_pos.y-6}
            append_rail_dir = dirs.north
         elseif rail_api_dir == dirs.southwest then
            append_rail_pos = {end_rail_pos.x-0, end_rail_pos.y-6}
            append_rail_dir = dirs.north
         end
      elseif end_rail_dir == dirs.northeast then
         if rail_api_dir == dirs.northeast then
            append_rail_pos = {end_rail_pos.x+2, end_rail_pos.y-4}
            append_rail_dir = dirs.northwest
         elseif rail_api_dir == dirs.east then
            append_rail_pos = {end_rail_pos.x+2, end_rail_pos.y-4}
            append_rail_dir = dirs.southeast
         end
      elseif end_rail_dir == dirs.east then
         if rail_api_dir == dirs.west then
            append_rail_pos = {end_rail_pos.x+4, end_rail_pos.y-2}
            append_rail_dir = dirs.east
         elseif rail_api_dir == dirs.northwest then
            append_rail_pos = {end_rail_pos.x+4, end_rail_pos.y-0}
            append_rail_dir = dirs.east
         end         
      elseif end_rail_dir == dirs.southeast then
         if rail_api_dir == dirs.southeast then
            append_rail_pos = {end_rail_pos.x+2, end_rail_pos.y+2}
            append_rail_dir = dirs.northeast
         elseif rail_api_dir == dirs.south then
            append_rail_pos = {end_rail_pos.x+2, end_rail_pos.y+2}
            append_rail_dir = dirs.southwest
         end
      elseif end_rail_dir == dirs.south then
         if rail_api_dir == dirs.north then
            append_rail_pos = {end_rail_pos.x-0, end_rail_pos.y+4}
            append_rail_dir = dirs.north
         elseif rail_api_dir == dirs.northeast then
            append_rail_pos = {end_rail_pos.x-2, end_rail_pos.y+4}
            append_rail_dir = dirs.north
         end
      elseif end_rail_dir == dirs.southwest then
         if rail_api_dir == dirs.southwest then
            append_rail_pos = {end_rail_pos.x-4, end_rail_pos.y+2}
            append_rail_dir = dirs.southeast
         elseif rail_api_dir == dirs.west then
            append_rail_pos = {end_rail_pos.x-4, end_rail_pos.y+2}
            append_rail_dir = dirs.northwest
         end
      elseif end_rail_dir == dirs.west then
         if rail_api_dir == dirs.east then
            append_rail_pos = {end_rail_pos.x-6, end_rail_pos.y-0}
            append_rail_dir = dirs.east
         elseif rail_api_dir == dirs.southeast then
            append_rail_pos = {end_rail_pos.x-6, end_rail_pos.y-2}
            append_rail_dir = dirs.east
         end 
      elseif end_rail_dir == dirs.northwest then
         if rail_api_dir == dirs.north then
            append_rail_pos = {end_rail_pos.x-4, end_rail_pos.y-4}
            append_rail_dir = dirs.northeast
         elseif rail_api_dir == dirs.northwest then
            append_rail_pos = {end_rail_pos.x-4, end_rail_pos.y-4}
            append_rail_dir = dirs.southwest
         end 
      end
   end
   
   --6. Clear trees and rocks nearby and check if the selected 2x2 space is free for building, else return
   if append_rail_pos == nil then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout(end_rail_dir .. " and " .. rail_api_dir .. ", rail appending direction error.",pindex)
      return
   end
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(append_rail_pos,4, pindex)
   if not surf.can_place_entity{name = "straight-rail", position = append_rail_pos, direction = append_rail_dir} then 
      --Check if you can build from cursor or if you have other rails here already
      -- local other_rails_present = false
      -- local ents = surf.find_entities_filtered{position = append_rail_pos}
      -- for i,ent in ipairs(ents) do
         -- if ent.name == "straight-rail" or ent.name == "curved-rail" then
            -- other_rails_present = true
         -- end
      -- end
      -- if game.get_player(pindex).can_build_from_cursor({name = "straight-rail", position = append_rail_pos, direction = append_rail_dir}) then--**maybe thisll work
         -- game.get_player(pindex).print("Can build from hand",{volume_modifier = 0})
      -- end
      -- if other_rails_present == true then
         -- game.get_player(pindex).print("Other rails present",{volume_modifier = 0})
      -- end
      --Patch a bug with South and West dirs in certain conditions such as after a train stop, where it is detected as North/East
      if end_rail_dir == dirs.east then
         append_rail_pos = {end_rail_pos.x-2, end_rail_pos.y-0}
      elseif end_rail_dir == dirs.north then
         append_rail_pos = {end_rail_pos.x-0, end_rail_pos.y+2}
      end 
      if not surf.can_place_entity{name = "straight-rail", position = append_rail_pos, direction = append_rail_dir} then 
         printout("Cannot place here to extend the rail.",pindex)
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         rendering.draw_circle{color = {1, 0, 0},radius = 0.5,width = 5,target = append_rail_pos,surface = surf,time_to_live = 120}
         return
      end
   end
   
   --7. Create the appended rail and subtract 1 rail from the hand.
   created_rail = surf.create_entity{name = "straight-rail", position = append_rail_pos, direction = append_rail_dir, force = game.forces.player}
   
   if not (created_rail ~= nil and created_rail.valid) then
      created_rail = game.get_player(pindex).build_from_cursor({name = "straight-rail", position = append_rail_pos, direction = append_rail_dir})
      if not (created_rail ~= nil and created_rail.valid) then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("Error: Invalid appended rail, try placing by hand.",pindex)
         rendering.draw_circle{color = {1, 0, 0},radius = 0.5,width = 5,target = append_rail_pos,surface = surf,time_to_live = 120}
         return
      end
   end
   
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 1
   game.get_player(pindex).play_sound{path = "entity-build/straight-rail"}
   
   --8. Check if the appended rail is with 4 tiles of a parallel rail. If so, delete it.
   if created_rail.valid and fa_rails.has_parallel_neighbor(created_rail,pindex) then
      game.get_player(pindex).mine_entity(created_rail,true)
	  game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Cannot place, parallel rail segments should be at least 4 tiles apart.",pindex)
   end
   
   --9. Check if the appended rail has created an intersection. If so, notify the player.
   if created_rail.valid and fa_rails.is_intersection_rail(created_rail,pindex) then
      printout("Intersection created.",pindex)
   end
      
end

--laterdo maybe revise build-item-in-hand for single placed rails so that you can have more control on it. Create a new place single rail function
--function place_single_rail(pindex)
--end

--Counts rails within range of a selected rail.
function fa_rails.count_rails_within_range(rail, range, pindex)
   --1. Scan around the rail for other rails
   local counter = 0
   local pos = rail.position
   local scan_area = {{pos.x-range,pos.y-range},{pos.x+range,pos.y+range}}
   local ents = game.get_player(pindex).surface.find_entities_filtered{area = scan_area, name = "straight-rail"}
   for i,other_rail in ipairs(ents) do
      --2. Increase counter for each straight rail
	  counter = counter + 1
   end
   ents = game.get_player(pindex).surface.find_entities_filtered{area = scan_area, name = "curved-rail"}
   for i,other_rail in ipairs(ents) do
      --3. Increase counter for each curved rail
	  counter = counter + 1
   end
   --Draw the range for visual debugging
   rendering.draw_circle{color = {0, 1, 0}, radius = range, width = range, target = rail, surface = rail.surface,time_to_live = 100}
   return counter
end

--Checks if the rail is parallel to another neighboring segment.
function fa_rails.has_parallel_neighbor(rail, pindex)
   --1. Scan around the rail for other rails
   local pos = rail.position
   local dir = rail.direction
   local range = 4
   if dir % 2 == 1 then
      range = 3
   end
   local scan_area = {{pos.x-range,pos.y-range},{pos.x+range,pos.y+range}} 
   local ents = game.get_player(pindex).surface.find_entities_filtered{area = scan_area, name = "straight-rail"}
   for i,other_rail in ipairs(ents) do
	 --2. For each rail, does it have the same rotation but a different segment? If yes return true.
	 local pos2 = other_rail.position
	  if rail.direction == other_rail.direction and not rail.is_rail_in_same_rail_segment_as(other_rail) then
	     --3. Also ignore cases where the rails are directly facing each other so that they can be connected
	     if (pos.x ~= pos2.x) and (pos.y ~= pos2.y) and (math.abs(pos.x - pos2.x) - math.abs(pos.y - pos2.y)) > 1 then
	        --4. Parallel neighbor found
		    rendering.draw_circle{color = {1, 0, 0},radius = range,width = range,target = pos,surface = rail.surface,time_to_live = 100}
	 	    return true
		 end
	  end
   end
   --4. No parallel neighbor found
   return false
end

--Checks if the rail is amid an intersection.
function fa_rails.is_intersection_rail(rail, pindex)
   --1. Scan around the rail for other rails
   local pos = rail.position
   local dir = rail.direction
   local scan_area = {{pos.x-1,pos.y-1},{pos.x+1,pos.y+1}} 
   local ents = game.get_player(pindex).surface.find_entities_filtered{area = scan_area, name = "straight-rail"}
   for i,other_rail in ipairs(ents) do
      --2. For each rail, does it have a different rotation and a different segment? If yes return true.
	  local dir_2 = other_rail.direction
	  dir = dir % dirs.south     --N/S or E/W does not matter
	  dir_2 = dir_2 % dirs.south --N/S or E/W does not matter
	  if dir ~= dir_2 and not rail.is_rail_in_same_rail_segment_as(other_rail) then
	     rendering.draw_circle{color = {0, 0, 1},radius = 1.5,width = 1.5,target = pos,surface = rail.surface,time_to_live = 100}
         return true
	  end
   end
   return false
end

function fa_rails.find_nearest_intersection(rail, pindex, radius_in)
   --1. Scan around the rail for other rails
   local radius = radius_in or 1000
   local pos = rail.position
   local scan_area = {{pos.x-radius,pos.y-radius},{pos.x+radius,pos.y+radius}} 
   local ents = game.get_player(pindex).surface.find_entities_filtered{area = scan_area, name = {"straight-rail","curved-rail"}}
   local nearest = nil
   local min_dist = radius
   for i,other_rail in ipairs(ents) do
      --2. For each rail, is it an intersection rail?
      if other_rail.valid and fa_rails.is_intersection_rail(other_rail, pindex) then
         local dist = math.ceil(util.distance(pos, other_rail.position))
		   --Set as nearest if valid
		   if dist < min_dist then
		      min_dist = dist
			   nearest = other_rail
		   end
      end
   end
   --Return the nearest found, possibly nil
   if nearest == nil then
     return nil, radius --Nothing within radius tiles!
   end
   rendering.draw_circle{color = {0, 0, 1}, radius = 2, width = 2, target = nearest.position, surface = nearest.surface, time_to_live = 60}
   return nearest, min_dist
end

--Places a chain signal pair around a rail depending on its direction. May fail if the spots are full.
function fa_rail_builder.place_chain_signal_pair(rail,pindex)
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local build_comment = "no comment"
   local successful = true
   local dir = rail.direction
   local pos = rail.position
   local surf = rail.surface
   local can_place_all = true
   
   --1. Check if signals can be placed, based on direction
   if dir == dirs.north or dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+1, pos.y}, direction = dirs.south, force = game.forces.player}
	  can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-2, pos.y}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east or dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x, pos.y-2}, direction = dirs.east, force = game.forces.player}
	  can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x, pos.y+1}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.northeast then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-1, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
	  can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+1, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.southwest then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-2, pos.y+1}, direction = dirs.northwest, force = game.forces.player}
	  can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+0, pos.y-1}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.southeast then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-1, pos.y-1}, direction = dirs.northeast, force = game.forces.player}
	  can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+1, pos.y+1}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northwest then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x-2, pos.y-2}, direction = dirs.northeast, force = game.forces.player}
	  can_place_all = can_place_all and surf.can_place_entity{name = "rail-chain-signal", position = {pos.x+0, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
   else
      successful = false
	  game.get_player(pindex).play_sound{path = "utility/cannot_build"}
	  build_comment = "direction error"
	  return successful, build_comment
   end
   
   if not can_place_all then
      successful = false
	  game.get_player(pindex).play_sound{path = "utility/cannot_build"}
	  build_comment = "cannot place"
	  return successful, build_comment
   end
   
   --2. Check if there are already chain signals or rail signals nearby. If yes, stop.
   local signals_found = 0
   local signals = surf.find_entities_filtered{position = pos, radius = 3, name="rail-chain-signal"}
   for i,signal in ipairs(signals) do
      signals_found = signals_found + 1
   end
   local signals = surf.find_entities_filtered{position = pos, radius = 3, name="rail-signal"}
   for i,signal in ipairs(signals) do
      signals_found = signals_found + 1
   end
   if signals_found > 0 then
      successful = false
	  game.get_player(pindex).play_sound{path = "utility/cannot_build"}
	  build_comment = "Too close to existing signals."
	  return successful, build_comment
   end
   
   --3. Check whether the player has enough rail chain signals.
   if not (stack.valid and stack.valid_for_read and stack.name == "rail-chain-signal" and stack.count >= 2) then
      --Check if the inventory has one instead
      if players[pindex].inventory.lua_inventory.get_item_count("rail-chain-signal") < 2 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         build_comment = "You need to have at least 2 rail chain signals on you."
		 successful = false
		 game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         return successful, build_comment
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail-chain-signal")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --4. Place the signals.
   if dir == dirs.north or dir == dirs.south then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+1, pos.y}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-2, pos.y}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east or dir == dirs.west then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x, pos.y-2}, direction = dirs.east, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x, pos.y+1}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.northeast then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-1, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+1, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.southwest then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-2, pos.y+1}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+0, pos.y-1}, direction = dirs.southeast, force = game.forces.player} 
   elseif dir == dirs.southeast then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-1, pos.y-1}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+1, pos.y+1}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northwest then
      surf.create_entity{name = "rail-chain-signal", position = {pos.x-2, pos.y-2}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "rail-chain-signal", position = {pos.x+0, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
   else
      successful = false
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      build_comment = "direction error"
      return successful, build_comment
   end
   
   --Reduce the signal count and restore the cursor and wrap up
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 2
   game.get_player(pindex).clear_cursor()
   
   game.get_player(pindex).play_sound{path = "entity-build/rail-chain-signal"}
   game.get_player(pindex).play_sound{path = "entity-build/rail-chain-signal"}
   return successful, build_comment
end

--Places a rail signal pair around a rail depending on its direction. May fail if the spots are full. Copy of chain signal function
function fa_rail_builder.place_rail_signal_pair(rail,pindex)
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local build_comment = "no comment"
   local successful = true
   local dir = rail.direction
   local pos = rail.position
   local surf = rail.surface
   local can_place_all = true
   
   --1. Check if signals can be placed, based on direction
   if dir == dirs.north or dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x+1, pos.y}, direction = dirs.south, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x-2, pos.y}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east or dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x, pos.y-2}, direction = dirs.east, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x, pos.y+1}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.northeast then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x-1, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x+1, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.southwest then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x-2, pos.y+1}, direction = dirs.northwest, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x+0, pos.y-1}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.southeast then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x-1, pos.y-1}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x+1, pos.y+1}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northwest then
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x-2, pos.y-2}, direction = dirs.northeast, force = game.forces.player}
      can_place_all = can_place_all and surf.can_place_entity{name = "rail-signal", position = {pos.x+0, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
   else
      successful = false
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      build_comment = "direction error"
      return successful, build_comment
   end
   
   if not can_place_all then
      successful = false
	  game.get_player(pindex).play_sound{path = "utility/cannot_build"}
	  build_comment = "cannot place"
	  return successful, build_comment
   end
   
   --2. Check if there are already chain signals or rail signals nearby. If yes, stop.
   local signals_found = 0
   local signals = surf.find_entities_filtered{position = pos, radius = 3, name="rail-chain-signal"}
   for i,signal in ipairs(signals) do
      signals_found = signals_found + 1
   end
   local signals = surf.find_entities_filtered{position = pos, radius = 3, name="rail-signal"}
   for i,signal in ipairs(signals) do
      signals_found = signals_found + 1
   end
   if signals_found > 0 then
      successful = false
	  game.get_player(pindex).play_sound{path = "utility/cannot_build"}
	  build_comment = "Too close to existing signals."
	  return successful, build_comment
   end
   
   --3. Check whether the player has enough rail chain signals.
   if not (stack.valid and stack.valid_for_read and stack.name == "rail-signal" and stack.count >= 2) then
      --Check if the inventory has one instead
      if players[pindex].inventory.lua_inventory.get_item_count("rail-signal") < 2 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         build_comment = "You need to have at least 2 rail signals on you."
		 successful = false
		 game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         return successful, build_comment
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("rail-signal")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --4. Place the signals.
   if dir == dirs.north or dir == dirs.south then
      surf.create_entity{name = "rail-signal", position = {pos.x+1, pos.y}, direction = dirs.south, force = game.forces.player}
      surf.create_entity{name = "rail-signal", position = {pos.x-2, pos.y}, direction = dirs.north, force = game.forces.player}
   elseif dir == dirs.east or dir == dirs.west then
      surf.create_entity{name = "rail-signal", position = {pos.x, pos.y-2}, direction = dirs.east, force = game.forces.player}
      surf.create_entity{name = "rail-signal", position = {pos.x, pos.y+1}, direction = dirs.west, force = game.forces.player}
   elseif dir == dirs.northeast then
      surf.create_entity{name = "rail-signal", position = {pos.x-1, pos.y-0}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "rail-signal", position = {pos.x+1, pos.y-2}, direction = dirs.southeast, force = game.forces.player}
   elseif dir == dirs.southwest then
      surf.create_entity{name = "rail-signal", position = {pos.x-2, pos.y+1}, direction = dirs.northwest, force = game.forces.player}
      surf.create_entity{name = "rail-signal", position = {pos.x+0, pos.y-1}, direction = dirs.southeast, force = game.forces.player} 
   elseif dir == dirs.southeast then
      surf.create_entity{name = "rail-signal", position = {pos.x-1, pos.y-1}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "rail-signal", position = {pos.x+1, pos.y+1}, direction = dirs.southwest, force = game.forces.player}
   elseif dir == dirs.northwest then
      surf.create_entity{name = "rail-signal", position = {pos.x-2, pos.y-2}, direction = dirs.northeast, force = game.forces.player}
      surf.create_entity{name = "rail-signal", position = {pos.x+0, pos.y+0}, direction = dirs.southwest, force = game.forces.player}
   else
      successful = false
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      build_comment = "direction error"
      return successful, build_comment
   end
   
   --Reduce the signal count and restore the cursor and wrap up
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 2
   game.get_player(pindex).clear_cursor()
   
   game.get_player(pindex).play_sound{path = "entity-build/rail-signal"}
   game.get_player(pindex).play_sound{path = "entity-build/rail-signal"}
   return successful, build_comment
end

--Deletes rail signals around a rail.
function fa_rail_builder.destroy_signals(rail)
   local chains = rail.surface.find_entities_filtered{position = rail.position, radius = 2, name = "rail-chain-signal"}
   for i,chain in ipairs(chains) do
      chain.destroy()
   end
   local signals = rail.surface.find_entities_filtered{position = rail.position, radius = 2, name = "rail-signal"}
   for i,signal in ipairs(signals) do
      signal.destroy()
   end
end

--Mines for the player the rail signals around a rail.
function fa_rails.mine_signals(rail,pindex)
   local chains = rail.surface.find_entities_filtered{position = rail.position, radius = 2, name = "rail-chain-signal"}
   for i,chain in ipairs(chains) do
      game.get_player(pindex).mine_entity(chain,true)
   end
   local signals = rail.surface.find_entities_filtered{position = rail.position, radius = 2, name = "rail-signal"}
   for i,signal in ipairs(signals) do
      game.get_player(pindex).mine_entity(signal,true)
   end
end

--Places a train stop facing the direction of the end rail.
function fa_rail_builder.build_train_stop(anchor_rail, pindex)
   local build_comment = ""
   local surf = game.get_player(pindex).surface
   local stack = game.get_player(pindex).cursor_stack
   local stack2 = nil
   local pos = nil
   local dir = -1
   local build_area = nil
   local can_place_all = true
   local is_end_rail
   
   --1. Firstly, check if the player has a train stop in hand
   if not (stack.valid and stack.valid_for_read and stack.name == "train-stop" and stack.count > 0) then
      --Check if the inventory has enough
      if players[pindex].inventory.lua_inventory.get_item_count("train-stop") < 1 then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("You need at least 1 train stop in your inventory to build this turn.", pindex)
         return
      else
         --Take from the inventory.
         stack2 = players[pindex].inventory.lua_inventory.find_item_stack("train-stop")
         game.get_player(pindex).cursor_stack.swap_stack(stack2)
         stack = game.get_player(pindex).cursor_stack
         players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      end
   end
   
   --2. Secondly, find the direction based on end rail or player direction
   is_end_rail, end_rail_dir, build_comment = fa_rails.check_end_rail(anchor_rail,pindex)
   if is_end_rail then
      dir = end_rail_dir
   else
      --Choose the dir based on player direction 
      turn_to_cursor_direction_cardinal(pindex)
      if anchor_rail.direction == dirs.north or anchor_rail.direction == dirs.south then
         if players[pindex].player_direction == dirs.north or players[pindex].player_direction == dirs.east then
            dir = dirs.north
         elseif players[pindex].player_direction == dirs.south or players[pindex].player_direction == dirs.west then
            dir = dirs.south
         end
      elseif anchor_rail.direction == dirs.east or anchor_rail.direction == dirs.west then
         if players[pindex].player_direction == dirs.north or players[pindex].player_direction == dirs.east then
            dir = dirs.east
         elseif players[pindex].player_direction == dirs.south or players[pindex].player_direction == dirs.west then
            dir = dirs.west
         end
      end
   end
   pos = anchor_rail.position
   if dir == dirs.northeast or dir == dirs.southeast or dir == dirs.southwest or dir == dirs.northwest then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("This structure is for horizontal or vertical end rails only.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --3. Clear trees and rocks in the build area
   temp1, build_comment = fa_mining_tools.clear_obstacles_in_circle(pos,3, pindex)
   
   --4. Check if every object can be placed
   if dir == dirs.north then 
      can_place_all = can_place_all and surf.can_place_entity{name = "train-stop", position = {pos.x+2, pos.y+0}, direction = dirs.north, force = game.forces.player}
      
   elseif dir == dirs.east then
      can_place_all = can_place_all and surf.can_place_entity{name = "train-stop", position = {pos.x+0, pos.y+2}, direction = dirs.east, force = game.forces.player}
      
   elseif dir == dirs.south then
      can_place_all = can_place_all and surf.can_place_entity{name = "train-stop", position = {pos.x-2, pos.y+0}, direction = dirs.south, force = game.forces.player}
      
   elseif dir == dirs.west then
      can_place_all = can_place_all and surf.can_place_entity{name = "train-stop", position = {pos.x-0, pos.y-2}, direction = dirs.west, force = game.forces.player}
      
   end
  
   if not can_place_all then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("Building area occupied, possibly by the player. Cursor mode recommended.", pindex)
      game.get_player(pindex).clear_cursor()
      return
   end
   
   --5. Build the five rail entities to create the structure 
   if dir == dirs.north then 
      surf.create_entity{name = "train-stop", position = {pos.x+2, pos.y+0}, direction = dirs.north, force = game.forces.player}
      
   elseif dir == dirs.east then
      surf.create_entity{name = "train-stop", position = {pos.x+0, pos.y+2}, direction = dirs.east, force = game.forces.player}
      
   elseif dir == dirs.south then
      surf.create_entity{name = "train-stop", position = {pos.x-2, pos.y+0}, direction = dirs.south, force = game.forces.player}
      
   elseif dir == dirs.west then
      surf.create_entity{name = "train-stop", position = {pos.x-0, pos.y-2}, direction = dirs.west, force = game.forces.player}
      
   end
   
   --6 Remove 5 rail units from the player's hand
   game.get_player(pindex).cursor_stack.count = game.get_player(pindex).cursor_stack.count - 1
   game.get_player(pindex).clear_cursor()
   
   --7. Sounds and results
   game.get_player(pindex).play_sound{path = "entity-build/train-stop"}
   printout("Train stop built facing" .. fa_utils.direction_lookup(dir) .. ", " .. build_comment, pindex)
   return
end

--Loads and opens the rail builder menu
function fa_rail_builder.open_menu(pindex, rail)
   if players[pindex].vanilla_mode then
      return 
   end
   --Set the player menu tracker to this menu
   players[pindex].menu = "rail_builder"
   players[pindex].in_menu = true
   players[pindex].move_queue = {}
   
   --Set the menu line counter to 0
   players[pindex].rail_builder.index = 0
   
   --Determine rail type
   local is_end_rail, end_dir, comment = fa_rails.check_end_rail(rail,pindex)
   local dir = rail.direction
   if is_end_rail then
      if dir == dirs.north or dir == dirs.east or dir == dirs.south or dir == dirs.west then 
         --Straight end rails
         players[pindex].rail_builder.rail_type = 1
         players[pindex].rail_builder.index_max = 8
      else 
         --Diagonal end rails
         players[pindex].rail_builder.rail_type = 2
         players[pindex].rail_builder.index_max = 2
      end
   else
      if dir == dirs.north or dir == dirs.east or dir == dirs.south or dir == dirs.west then 
         --Straight mid rails
         players[pindex].rail_builder.rail_type = 3
         players[pindex].rail_builder.index_max = 3
      else
         --Diagonal mid rails
         players[pindex].rail_builder.rail_type = 4
         players[pindex].rail_builder.index_max = 3
      end
   end
   
   --Play sound
   game.get_player(pindex).play_sound{path = "Open-Inventory-Sound"}
   
   --Load menu 
   players[pindex].rail_builder.rail = rail
   fa_rail_builder.run_menu(pindex, false)
end

--Resets and closes the rail builder menu
function fa_rail_builder.close_menu(pindex, mute_in)
   local mute = mute_in or false
   --Set the player menu tracker to none
   players[pindex].menu = "none"
   players[pindex].in_menu = false

   --Set the menu line counter to 0
   players[pindex].rail_builder.index = 0
   
   --play sound
   if not mute then
      game.get_player(pindex).play_sound{path="Close-Inventory-Sound"}
   end
end

--Moves up the rail builder menu
function fa_rail_builder.menu_up(pindex)
   --Decrement the index
   players[pindex].rail_builder.index = players[pindex].rail_builder.index - 1

   --Check the index against the limit
   if players[pindex].rail_builder.index < 0 then
      players[pindex].rail_builder.index = 0
      game.get_player(pindex).play_sound{path = "inventory-edge"}
   else
      --Play sound
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
   end
   
   --Load menu 
   fa_rail_builder.run_menu(pindex, false)
end

--Moves down the rail buidler menu
function fa_rail_builder.menu_down(pindex)
   --Increment the index
   players[pindex].rail_builder.index = players[pindex].rail_builder.index + 1

   --Check the index against the limit
   if players[pindex].rail_builder.index > players[pindex].rail_builder.index_max then
      players[pindex].rail_builder.index = players[pindex].rail_builder.index_max
      game.get_player(pindex).play_sound{path = "inventory-edge"}
   else
      --Play sound
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
   end
   
   --Load menu 
   fa_rail_builder.run_menu(pindex, false)
end

--Builder menu to build rail structures
function fa_rail_builder.run_menu(pindex, clicked_in)
   local clicked = clicked_in
   local comment = ""
   local menu_line = players[pindex].rail_builder.index
   local rail_type = players[pindex].rail_builder.rail_type
   local rail = players[pindex].rail_builder.rail
   
   if rail == nil then
      comment = " Rail nil error "
      printout(comment,pindex)
      fa_rail_builder.close_menu(pindex, false)
      return
   end
   
   if menu_line == 0 then
	  comment = comment .. "Select a structure to build by going up or down this menu, attempt to build it via LEFT BRACKET, "
      printout(comment,pindex)
      return
   end
   
   if rail_type == 1 then
      --Straight end rails
      if menu_line == 1 then
         if not clicked then
            comment = comment .. "Left turn 45 degrees"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_rail_turn_left_45_degrees(rail, pindex)
         end
      elseif menu_line == 2 then
         if not clicked then
            comment = comment .. "Right turn 45 degrees"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_rail_turn_right_45_degrees(rail, pindex)
         end
      elseif menu_line == 3 then
         if not clicked then
            comment = comment .. "Left turn 90 degrees"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_rail_turn_left_90_degrees(rail, pindex)
         end
      elseif menu_line == 4 then
         if not clicked then
            comment = comment .. "Right turn 90 degrees"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_rail_turn_right_90_degrees(rail, pindex)
         end
      elseif menu_line == 5 then
         if not clicked then
            comment = comment .. "Train stop facing end rail direction"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_train_stop(rail, pindex)
         end
      elseif menu_line == 6 then
         if not clicked then
            comment = comment .. "Rail fork with 2 exits"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_fork_at_end_rail(rail, pindex, false)
         end
      elseif menu_line == 7 then
         if not clicked then
            comment = comment .. "Rail fork with 3 exits"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_fork_at_end_rail(rail, pindex, true)
         end
      elseif menu_line == 8 then
         if not clicked then
            comment = comment .. "Rail bypass junction"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_rail_bypass_junction(rail, pindex)
         end
      end
   elseif rail_type == 2 then
      --Diagonal end rails
      if menu_line == 1 then
         if not clicked then
            comment = comment .. "Left turn 45 degrees"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_rail_turn_left_45_degrees(rail, pindex)
         end
      elseif menu_line == 2 then
         if not clicked then
            comment = comment .. "Right turn 45 degrees"
            printout(comment,pindex)
         else
            --Build it here
            fa_rail_builder.build_rail_turn_right_45_degrees(rail, pindex)
         end
      end
   elseif rail_type == 3 then
      --Straight mid rails
	  if menu_line == 1 then
         if not clicked then
            comment = comment .. "Pair of chain rail signals."
            printout(comment,pindex)
         else
            local success, build_comment = fa_rail_builder.place_chain_signal_pair(rail,pindex)
            if success then
               comment = "Chain signals placed."
            else
               comment = comment .. build_comment
            end
               printout(comment,pindex)
            end
	  elseif menu_line == 2 then
         if not clicked then
            comment = comment .. "Pair of regular rail signals, warning: do not use regular rail signals unless you are sure about what you are doing because trains can easily get deadlocked at them"
            printout(comment,pindex)
         else
            local success, build_comment = fa_rail_builder.place_rail_signal_pair(rail,pindex)
            if success then
               comment = "Rail signals placed, warning: do not use regular rail signals unless you are sure about what you are doing because trains can easily get deadlocked at them"
            else
               comment = comment .. build_comment
            end
            printout(comment,pindex)
         end
     elseif menu_line == 3 then
         if not clicked then
            comment = comment .. "Clear rail signals"
            printout(comment,pindex)
         else
            fa_rails.mine_signals(rail,pindex)
            printout("Signals cleared.",pindex)
         end
      end
   elseif rail_type == 4 then
      --Diagonal mid rails
      if menu_line == 1 then
         if not clicked then
            comment = comment .. "Pair of chain rail signals." 
            printout(comment,pindex)
         else
            local success, build_comment = fa_rail_builder.place_chain_signal_pair(rail,pindex)
            if success then
               comment = "Chain signals placed."
            else
               comment = comment .. build_comment
            end
               printout(comment,pindex)
            end
      elseif menu_line == 2 then
         if not clicked then
            comment = comment .. "Pair of regular rail signals, warning: do not use regular rail signals unless you are sure about what you are doing because trains can easily get deadlocked at them"
            printout(comment,pindex)
         else
            local success, build_comment = fa_rail_builder.place_rail_signal_pair(rail,pindex)
            if success then
               comment = "Rail signals placed, warning: do not use regular rail signals unless you are sure about what you are doing because trains can easily get deadlocked at them"
            else
               comment = comment .. build_comment
            end
            printout(comment,pindex)
         end
	   elseif menu_line == 3 then
         if not clicked then
            comment = comment .. "Clear rail signals"
            printout(comment,pindex)
         else
            fa_rails.mine_signals(rail,pindex)
            printout("Signals cleared.",pindex)
         end
      end
   end
   return
end

--Plays a train track alert sound for every player standing on or facing train tracks that meet the condition.
function fa_rails.check_and_play_train_track_alert_sounds(step)
   for pindex, player in pairs(players) do
      --Check if the player is standing on a rail
      local p = game.get_player(pindex)
      local floor_ent = p.surface.find_entities_filtered{position = p.position, limit = 1}[1]
      local facing_ent = players[p.index].tile.ents[1]
      local found_rail = nil
      local skip = false
      if p.driving then
         skip = true
      elseif floor_ent ~= nil and floor_ent.valid and (floor_ent.name == "straight-rail" or floor_ent.name == "curved-rail") then
         found_rail = floor_ent
      elseif facing_ent ~= nil and facing_ent.valid and (facing_ent.name == "straight-rail" or facing_ent.name == "curved-rail") then
         found_rail = facing_ent
      else
         --Check further around the player because the other scans do not cover the back
         local floor_ent_2 = p.surface.find_entities_filtered{name = {"straight-rail","curved-rail"}, position = p.position, radius = 1, limit = 1}[1]
         if floor_ent_2 ~= nil and floor_ent_2.valid then
            found_rail = floor_ent_2
         else
            skip = true
         end
      end
	  
      --Condition for step 1: Any moving trains nearby (within 400 tiles)
      if not skip and step == 1 then
         local trains = p.surface.get_trains()
         for i,train in ipairs(trains) do
            if train.speed ~= 0 and (util.distance(p.position,train.front_stock.position) < 400 or util.distance(p.position,train.back_stock.position) < 400) then 
               p.play_sound{path = "train-alert-low"}
               rendering.draw_circle{color = {1, 1, 0},radius = 2,width = 2,target = found_rail.position,surface = found_rail.surface,time_to_live = 15}
            end
         end
      --Condition for step 2: Any moving trains nearby (within 200 tiles), and heading towards the player
      elseif not skip and step == 2 then
	     local trains = p.surface.get_trains()
         for i,train in ipairs(trains) do
            if  train.speed ~= 0 and (util.distance(p.position,train.front_stock.position) < 200 or util.distance(p.position,train.back_stock.position) < 200)
            and ((train.speed > 0 and util.distance(p.position,train.front_stock.position) <= util.distance(p.position,train.back_stock.position)) 
            or   (train.speed < 0 and util.distance(p.position,train.front_stock.position) >= util.distance(p.position,train.back_stock.position))) then 
               p.play_sound{path = "train-alert-low"}
               rendering.draw_circle{color = {1, 0.5, 0},radius = 3,width = 4,target = found_rail.position,surface = found_rail.surface,time_to_live = 15}
            end
         end
      --Condition for step 3: Any moving trains in the same rail block, and heading towards the player OR if the block inbound signals are yellow. More urgent sound if also within 200 distance of the player
      elseif not skip and step == 3 then
         local trains = p.surface.get_trains()
         for i,train in ipairs(trains) do
            if   train.speed ~= 0 and (found_rail.is_rail_in_same_rail_block_as(train.front_rail) or found_rail.is_rail_in_same_rail_block_as(train.back_rail))
            and ((train.speed > 0 and util.distance(p.position,train.front_stock.position) <= util.distance(p.position,train.back_stock.position)) 
            or   (train.speed < 0 and util.distance(p.position,train.front_stock.position) >= util.distance(p.position,train.back_stock.position))) then 
               if (util.distance(p.position,train.front_stock.position) < 200 or util.distance(p.position,train.back_stock.position) < 200) then
                  p.play_sound{path = "train-alert-high"} 
                  rendering.draw_circle{color = {1, 0.0, 0},radius = 4,width = 8,target = found_rail.position,surface = found_rail.surface,time_to_live = 15}
               else
                  p.play_sound{path = "train-alert-low"}
                  rendering.draw_circle{color = {1, 0.4, 0},radius = 4,width = 8,target = found_rail.position,surface = found_rail.surface,time_to_live = 15}
               end
            end
         end
         local signals = found_rail.get_inbound_signals()
         for i,signal in ipairs(signals) do
            if signal.signal_state == defines.signal_state.reserved then
               for i,train in ipairs(trains) do
                  if (util.distance(p.position,train.front_stock.position) < 200 or util.distance(p.position,train.back_stock.position) < 200) then
                     p.play_sound{path = "train-alert-high"} 
                     rendering.draw_circle{color = {1, 0.0, 0},radius = 4,width = 8,target = found_rail.position,surface = found_rail.surface,time_to_live = 15}
                  else
                     p.play_sound{path = "train-alert-low"}
                     rendering.draw_circle{color = {1, 0.4, 0},radius = 4,width = 8,target = found_rail.position,surface = found_rail.surface,time_to_live = 15}
                  end
               end
            end
         end
      end
     
   end
end

return {rails = fa_rails, rail_builder = fa_rail_builder}
