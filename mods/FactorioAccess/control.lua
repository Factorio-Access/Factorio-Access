require('zoom')
require('rails-and-trains')
require('worker-robots')
local localising=require('localising')
require('equipment-and-combat')

groups = {}
entity_types = {}
production_types = {}
building_types = {}
dirs = defines.direction

local util = require('util')

local function squared_distance(pos1, pos2)
   local offset = {x = pos1.x - pos2.x, y = pos1.y - pos2.y}
   local result = offset.x * offset.x + offset.y * offset.y
   return result
end

local directions={
   [defines.direction.north]="North",
   [defines.direction.northeast]="Northeast",
   [defines.direction.east]="East",
   [defines.direction.southeast]="Southeast",
   [defines.direction.south]="South",
   [defines.direction.southwest]="Southwest",
   [defines.direction.west]="West",
   [defines.direction.northwest]="Northwest",
   [8] = ""
}

local function dir_dist(pos1,pos2)
   local x1 = pos1.x
   local x2 = pos2.x
   local dx = x2 - x1
   local y1 = pos1.y
   local y2 = pos2.y
   local dy = y2 - y1
   if dx == 0 and dy == 0 then
      return {8,0}
   end
   local dir = math.atan2(dy,dx) --scaled -pi to pi 0 being east
   dir = dir + math.sin(4*dir)/4 --bias towards the diagonals
   dir = dir/math.pi -- now scaled as -0.5 north, 0 east, 0.5 south
   dir=math.floor(dir*defines.direction.south + defines.direction.east + 0.5) --now scaled correctly
   dir=dir%(2*defines.direction.south) --now wrapped correctly
   local dist = math.sqrt(dx*dx+dy*dy)
   return {dir, dist}
end

local function dir(pos1,pos2)
   return dir_dist(pos1,pos2)[1]
end

local function direction (pos1, pos2)
   return directions[dir(pos1,pos2)]
end

local function distance ( pos1, pos2)
   return dir_dist( pos1, pos2)[2]
end

local function dir_dist_locale_h(dir_dist)
   return {"access.dir-dist",{"access.direction",dir_dist[1]},math.floor(dir_dist[2]+0.5)}
end

local function dir_dist_locale(pos1,pos2)
   return dir_dist_locale_h( dir_dist(pos1,pos2) )
end

local function ent_name_locale(ent)
   if ent.name == "water" then
      print("todo: water isn't an entity")
      return {"gui-map-generator.water"}
   end
   if ent.name == "forest" then
      print("todo: forest isn't an entity")
      return {"access.forest"}
   end
   if not game.entity_prototypes[ent.name] then
      error(ent.name .. " is not an entity")
   end
   return ent.localised_name or game.entity_prototypes[ent.name].localised_name
end

function nearest_edge(edges, pos, name)
   local pos = table.deepcopy(pos)
   if name == "forest" then
      pos.x = pos.x / 8 
      pos.y = pos.y / 8 
   end
   local result = {}
   local min = math.huge
   for str, b in pairs(edges) do
      local edge_pos = str2pos(str)
      local d = distance(pos, edge_pos)
      if d < min then
         result = edge_pos
         min = d
      end
   end
   if name == "forest" then
      result.x = result.x * 8 - 4
      result.y = result.y * 8 - 4
   end
   return result
end

function scale_area(area, factor)
   result = table.deepcopy(area)
   result.left_top.x = area.left_top.x * factor
   result.left_top.y = area.left_top.y * factor
   result.right_bottom.x = area.right_bottom.x * factor
   result.right_bottom.y = area.right_bottom.y * factor
   return result
end
function area_edge(area,dir,pos,name)
   local adjusted_area = table.deepcopy(area)
   if name == "forest" then
      local chunk_size = 8
      adjusted_area.left_top.x = adjusted_area.left_top.x / chunk_size
      adjusted_area.left_top.y = adjusted_area.left_top.y / chunk_size
      adjusted_area.right_bottom.x = adjusted_area.right_bottom.x / chunk_size
      adjusted_area.right_bottom.y = adjusted_area.right_bottom.y / chunk_size
   end
   if dir == 0 then
      if adjusted_area.left_top.y == math.floor(pos.y) then
         return true
      else
         return false
      end
   elseif dir == 2 then
      if adjusted_area.right_bottom.x == math.ceil( .001 + pos.x) then
         return true
      else
         return false
      end
   elseif dir == 4 then
      if adjusted_area.right_bottom.y == math.ceil(.001+pos.y) then
         return true
      else
         return false
      end

   elseif dir == 6 then
      if adjusted_area.left_top.x == math.floor(pos.x) then
         return true
      else
         return false
      end
   end
end

function table_concat (T1, T2)
   if T2 == nil then
      return
   end
   if T1 == nil then
      T1 = {}
   end
   for i, v in pairs(T2) do
         table.insert(T1, v)
   end
end

function pos2str (pos)
   return pos.x .. " " .. pos.y
end
function str2pos(str)
   local t = {}
   for s in string.gmatch(str, "([^%s]+)") do
      table.insert(t, s)
   end
      return {x = t[1], y = t[2]}
end

function get_selected_ent(pindex)
   local tile=players[pindex].tile
   local ent
   while true do
      if tile.index > #tile.ents then
         tile.index = #tile.ents
      end
      if tile.index == 0 then
         return nil
      end
      ent = tile.ents[tile.index]
      if not ent then
         print(serpent.line(tile.ents),tile.index,ent)
      end
      if ent.valid then
         return ent
      end
      table.remove(tile.ents,tile.index)
   end
end

function find_islands(surf, area, pindex)
   local islands = {}
   local ents = surf.find_entities_filtered{area = area, type = "resource"}
   local waters = surf.find_tiles_filtered{area = area, name = "water"}
   local trents = surf.find_entities_filtered{area = area, type = "tree"}
--   if trents ~= nil and #trents > 0 then      printout("trees galore", pindex) end
   local i = 1
   while i <= #trents do
      local trent = trents[i]
      local check = (trent.position.x >= area.left_top.x and trent.position.y >= area.left_top.y and trent.position.x < area.right_bottom.x and trent.position.y < area.right_bottom.y)
  
      if check == false then
         table.remove(trents, i) 
      else
         i = i + 1 
      end
   end
   if #trents > 0 then
      --printout("trees galore", pindex) **beta
   end
   if #ents == 0 and #waters == 0 and #trents == 0 then return {} end

   for i, ent in ipairs(ents) do
      local destroy_id = script.register_on_entity_destroyed(ent)
      players[pindex].destroyed[destroy_id] = {name = ent.name, position = ent.position, type = ent.type, area = ent.bounding_box}
      if islands[ent.name] == nil then
         islands[ent.name] = {
            name = ent.name,
            groups = {},
            resources = {},
            edges = {},
         neighbors = {}
         }
      end
      islands[ent.name].groups[i] = {pos2str(ent.position)}
      islands[ent.name].resources[pos2str(ent.position)] = {group=i, edge = false}
   end
   if #waters > 0 then
      islands["water"] = {
         name = "water",
         groups = {},
         resources = {},
         edges = {},
      neighbors = {}
      }
   end
   for i, water in pairs(waters) do
      local str = pos2str(water.position)
      if islands["water"].resources[str] == nil then
         islands["water"].groups[i] = {str}
         islands["water"].resources[str] = {group=i, edge = false}
      end
   end
   if #trents > 0 then
      islands["forest"] = {
         name = "forest",
         groups = {},
         resources = {},
         edges = {},
      neighbors = {}
      }
   end
   for i, trent in pairs(trents) do
      local destroy_id = script.register_on_entity_destroyed(trent)
      players[pindex].destroyed[destroy_id] = {name = trent.name, position = trent.position, type = trent.type, area = trent.bounding_box}

      local pos = table.deepcopy(trent.position)
      pos.x = math.floor(pos.x/8)
      pos.y = math.floor(pos.y/8)

      local str = pos2str(pos)

      if islands["forest"].resources[str] == nil then
         islands["forest"].groups[i] = {str}
         islands["forest"].resources[str] = {group=i, edge = false, count = 1}
      else         
         islands["forest"].resources[str].count = islands["forest"].resources[str].count + 1
      end
   end

   for name, entry in pairs(islands) do
      for pos, resource in pairs(entry.resources) do
         local position = str2pos(pos)
         local adj = {}
         for dir = 0, 7 do
            adj[dir] = pos2str(offset_position(position, dir, 1))         
         end
         local new_group = resource.group
         for dir, index in ipairs(adj) do
            if entry.resources[index] == nil then
               resource.edge = true
            else
               new_group = math.min(new_group, entry.resources[index].group)
            end        
         end
         if resource.edge then
--            table.insert(entry.edges, pos)
            entry.edges[pos] = false
            if area_edge(area, 0, position, name) then
               entry.neighbors[0] = true
            entry.edges[pos] = true
            end
            if area_edge(area, 6, position, name) then
               entry.neighbors[6] = true
            entry.edges[pos] = true
            end
            if area_edge(area, 4, position, name) then
               entry.neighbors[4] = true
            entry.edges[pos] = true
         end
         if area_edge(area, 2, position, name) then
               entry.neighbors[2] = true
               entry.edges[pos] = true
            end
         end
         table.insert(adj, pos)
         for dir, index in ipairs(adj) do
            if entry.resources[index] ~= nil and entry.resources[index].group ~= new_group then
               local old_group = entry.resources[index].group
               table_concat(entry.groups[new_group], entry.groups[old_group])
               for i, index in pairs(entry.groups[old_group]) do
                  entry.resources[index].group = new_group
               end
               entry.groups[old_group] = nil
            end
         end

      end
   end
   return islands
end

function breakup_string(str)
   result = {""}
   if table_size(str) > 20 then
      local i = 0
      while i < #str do
         if i%20 == 0 then
         table.insert(result, {""})
         end
         table.insert(result[math.ceil((i+1)/20)+1], table.deepcopy(str[i+1]))
         i = i + 1
      end
      return result
   else
      return str
   end
end


--[[Function to increase/decrease the bar (restricted slots) of a given chest/container by a given amount, while protecting its lower and upper bounds. 
* Returns the verbal explanation to print out. 
* amount = number of slots to change, set negative value for a decrease.
]]
function increment_inventory_bar(ent, amount)
   local inventory = ent.get_inventory(defines.inventory.chest)
   
   --Checks
   if not inventory then
      return {"access.failed-inventory-limit-ajust-notcontainter"}
   end
   if not inventory.supports_bar() then
      return {"access.failed-inventory-limit-ajust-no-limit"}
   end
   
   local max_bar = #inventory + 1
   local current_bar = inventory.get_bar()
   
   --Change bar
   amount = amount or 1
   current_bar = current_bar + amount
   
   if current_bar < 1 then
      current_bar = 1
   elseif current_bar > max_bar then
      current_bar = max_bar
   end
   
   inventory.set_bar(current_bar)
   
   --Return result
   local value = current_bar -1 --Mismatch correction
   if current_bar == max_bar then
      value = {"gui.all"}
      current_bar=1000
   else
      current_bar = value 
   end
   return {"access.inventory-limit-status",value,current_bar}
end

--Brief extra entity info is given here. If the parameter info_comes_after_indexing is false, then this info distinguishes the entity with its description as a new line of the scanner list, such as how assembling machines with different recipes are listed separately.
function extra_info_for_scan_list(ent,pindex,info_comes_after_indexing)
   local result = ""
   --Drills
   if ent.name ~= "water" and ent.type == "mining-drill"  then
      local pos = ent.position
      local radius = ent.prototype.mining_drill_radius
      local area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}
      local resources = ent.surface.find_entities_filtered{area = area, type = "resource"}
      local dict = {}
      for i, resource in pairs(resources) do
         if dict[resource.name] == nil then
            dict[resource.name] = resource.amount
         else
            dict[resource.name] = dict[resource.name] + resource.amount
         end
      end
      if table_size(dict) > 0 then
         result = result .. " mining From "
         for i, amount in pairs(dict) do
            result = result .. " " .. i .. " "
         end
      else
         result = result .. " out of minable resources"
      end
   end
   --Assemblers and furnaces
   pcall(function()
      if ent.get_recipe() ~= nil then
         result = result .. " producing " .. ent.get_recipe().name
      end
   end)
   
   if ent.type == "container" or ent.type == "logistic-container" then --Chests are identified by whether they contain nothing a specific item, or simply various items
      local itemset = ent.get_inventory(defines.inventory.chest).get_contents()
      local itemtable = {}
      for name, count in pairs(itemset) do
         table.insert(itemtable, {name = name, count = count})
      end
      --table.sort(itemtable, function(k1, k2)
      --   return k1.count > k2.count
      --end)
      if #itemtable == 0 then
         result = result .. " empty "
      elseif #itemtable == 1 then
         result = result .. " with " .. itemtable[1].name
      elseif #itemtable > 1 then
         result = result .. " with various items "
      end
   elseif ent.type == "unit-spawner" then
      --Group by pollution level
      if ent.absorbed_pollution > 0 then
         result = " polluted lightly "
         if ent.absorbed_pollution > 99 then
            result = " polluted heavily "
         end
      else
         local pos = ent.position
         local pollution_nearby = false
         pollution_nearby = pollution_nearby and (ent.surface.get_pollution({pos.x+00,pos.y+00}) > 0)
         pollution_nearby = pollution_nearby and (ent.surface.get_pollution({pos.x+33,pos.y+00}) > 0)
         pollution_nearby = pollution_nearby and (ent.surface.get_pollution({pos.x-33,pos.y+00}) > 0)
         pollution_nearby = pollution_nearby and (ent.surface.get_pollution({pos.x+00,pos.y+33}) > 0)
         pollution_nearby = pollution_nearby and (ent.surface.get_pollution({pos.x+00,pos.y-33}) > 0)
         if pollution_nearby then
            result = " almost polluted "--**laterdo bug: this does not seem to ever be reached
         else
            result = " normal "
         end
      end
   end
   
   if info_comes_after_indexing == true and ent.train ~= nil and ent.train.valid then
      result = result .. " of train " .. get_train_name(ent.train)
   elseif ent.name == "character" then
      local p = ent.player
      local p2 = ent.associated_player
      if p ~= nil and p.valid and p.name ~= nil and p.name ~= "" then
         result = result .. " " .. p.name 
      elseif p2 ~= nil and p2.valid and p2.name ~= nil and p2.name ~= "" then
         result = result .. " " .. p2.name 
      elseif p ~= nil and p.valid and p.index == pindex then
         result = result .. " you "
      elseif pindex ~= nil then
         result = result .. " " .. pindex
      else
         result = result .. " X "
      end
   elseif ent.name == "character-corpse" then
      if ent.character_corpse_player_index == pindex then
         result = result .. " of your character "
      elseif ent.character_corpse_player_index ~= nil then
         result = result .. " of another character "
      end
   elseif info_comes_after_indexing == true and ent.name == "train-stop" then
      result = result .. " " .. ent.backer_name
   elseif ent.name == "forest" then
      result = result .. classify_forest(ent.position,pindex,true)
   elseif ent.name == "roboport" then
      result = result .. " of network " .. get_network_name(ent)
   end
   
   return result
end

function classify_forest(position,pindex,drawing)
   local tree_count = 0
   local tree_group = game.get_player(pindex).surface.find_entities_filtered{type = "tree", position = position, radius = 16, limit = 15}
   if drawing then
      rendering.draw_circle{color = {0, 1, 0.25},radius = 16,width = 4,target = position, surface = game.get_player(pindex).surface, time_to_live = 60, draw_on_ground = true}
   end
   for i,tree in ipairs(tree_group) do
      tree_count = tree_count + 1
      if drawing then
         rendering.draw_circle{color = {0, 1, 0.5},radius = 1,width = 4,target = tree.position, surface = tree.surface, time_to_live = 60, draw_on_ground = true}
      end
   end
   if tree_count < 1 then
      return "empty"
   elseif tree_count < 6 then
      return "patch"
   elseif tree_count < 11 then
      return "sparse"
   else
      return "dense"
   end
end

function nudge_key(direction, event)--
   local pindex = event.player_index
   if not check_for_player(pindex) or players[pindex].menu == "prompt" then
      return 
   end
   local ent = get_selected_ent(pindex)
   if ent and ent.valid then
      if ent.force == game.get_player(pindex).force then
         local old_pos = ent.position
         local new_pos = offset_position(ent.position,direction,1)
         local temporary_teleported = false
         local actually_teleported = false
         --First teleport the ent to 0,0 temporarily
         temporary_teleported = ent.teleport({0,0})
         if not temporary_teleported then
            game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            printout({"access.failed-to-nudge"}, pindex)
            return 
         end
         --Now check if the ent can be placed at its new location, and proceed or revert accordingly
         if ent.surface.can_place_entity{name = ent.name, position = new_pos, direction = ent.direction} then
            actually_teleported = ent.teleport(new_pos)
         else
            actually_teleported = ent.teleport(old_pos)
            game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            printout({"access.failed-to-nudge"}, pindex)
            return 
         end
         if not actually_teleported then
            printout({"access.failed-to-nudge"}, pindex)
            return 
         else
            --Successfully teleported and so nudged
            printout({"access.nudged-one-direction",{"access.direction",direction}}, pindex)
            if players[pindex].cursor then
               players[pindex].cursor_pos = offset_position(players[pindex].cursor_pos,direction,1)
               cursor_highlight(pindex, ent, "train-visualization")
               sync_build_arrow(pindex)
            end
            if ent.type == "electric-pole" then 
               -- laterdo **bugfix when nudged electric poles have extra wire reach, cut wires
               -- if ent.clone{position = new_pos, surface = ent.surface, force = ent.force, create_build_effect_smoke = false} == true then
                  -- ent.destroy{}
               -- end
            end
         end
      end
   else
      printout("Nudged nothing.", pindex)
   end
   
end

--The travel part of the structure travel feature.
function move_cursor_structure(pindex, dir)
   game.get_player(pindex).game_view_settings.update_entity_selection = true
   local direction = players[pindex].structure_travel.direction
   local adjusted = {}
   adjusted[0] = "north"
   adjusted[2] = "east"
   adjusted[4] = "south"
   adjusted[6] = "west"
   
   local network = players[pindex].structure_travel.network
   local current = players[pindex].structure_travel.current
   local index = players[pindex].structure_travel.index
   if direction == "none" then
      if #network[current][adjusted[(0 + dir) %8]] > 0 then
         players[pindex].structure_travel.direction = adjusted[(0 + dir)%8]
         players[pindex].structure_travel.index = 1
         local index = players[pindex].structure_travel.index
         local dx = network[current][adjusted[(0 + dir)%8]][index].dx
         local dy = network[current][adjusted[(0 + dir) %8]][index].dy
         local description = ""
         if math.floor(math.abs(dx)+ .5) ~= 0 then
            if dx < 0 then
               description = description .. math.floor(math.abs(dx)+.5) .. " " .. "tiles west, "
            elseif dx > 0 then
               description = description .. math.floor(math.abs(dx)+.5) .. " " .. "tiles east, "
            end
         end
         if math.floor(math.abs(dy)+ .5) ~= 0 then
            if dy < 0 then
               description = description .. math.floor(math.abs(dy)+.5) .. " " .. "tiles north, "
            elseif dy > 0 then
               description = description .. math.floor(math.abs(dy)+.5) .. " " .. "tiles south, "
            end
         end
         local ent = network[network[current][adjusted[(0 + dir) %8]][index].num]
         if ent.ent.valid then
            move_cursor_map(ent.ent.position,pindex)
            players[pindex].cursor_pos = ent.ent.position
            --Case 1: Proposing a new structure
            printout("To " .. ent.name .. " " .. extra_info_for_scan_list(ent.ent,pindex,true) .. ", " .. description  .. ", " .. index .. " of " .. #network[current][adjusted[(0 + dir) % 8]], pindex)
         else
            printout("Missing " .. ent.name .. " " .. description, pindex) 
         end
      else
         printout("There are no buildings directly " .. adjusted[(0 + dir) %8] .. " of this one.", pindex)
      end
   elseif direction == adjusted[(4 + dir)%8] then
      players[pindex].structure_travel.direction = "none"
      local description = ""
      if #network[current].north > 0 then
         description = description .. ", " .. #network[current].north .. " connections north,"
      end
      if #network[current].east > 0 then
         description = description .. ", " .. #network[current].east .. " connections east,"
      end
      if #network[current].south > 0 then
         description = description .. ", " .. #network[current].south .. " connections south,"
      end
      if #network[current].west > 0 then
         description = description .. ", " .. #network[current].west .. " connections west,"
      end
      if description == "" then
         description = "No nearby buildings."
      end
      local ent = network[current]
      if ent.ent.valid then
         move_cursor_map(ent.ent.position,pindex)
         players[pindex].cursor_pos = ent.ent.position
         --Case 2: Returning to the current structure
         printout("Back at " .. ent.name .. " " .. extra_info_for_scan_list(ent.ent,pindex,true) .. ", " .. description, pindex)
      else
         printout("Missing " .. ent.name .. " " .. description, pindex)
      end
   elseif direction == adjusted[(0 + dir) %8] then
      players[pindex].structure_travel.direction = "none"
      players[pindex].structure_travel.current = network[current][adjusted[(0 + dir) %8]][index].num
      local current = players[pindex].structure_travel.current
         
      local description = ""
      if #network[current].north > 0 then
         description = description .. ", " .. #network[current].north .. " connections north,"
      end
      if #network[current].east > 0 then
         description = description .. ", " .. #network[current].east .. " connections east,"
      end
      if #network[current].south > 0 then
         description = description .. ", " .. #network[current].south .. " connections south,"
      end
      if #network[current].west > 0 then
         description = description .. ", " .. #network[current].west .. " connections west,"
      end
      if description == "" then
         description = "No nearby buildings."
      end
      local ent = network[current]
     if ent.ent.valid then
         move_cursor_map(ent.ent.position,pindex)
         players[pindex].cursor_pos = ent.ent.position
         --Case 3: Moved to the new structure
         printout("Now at " .. ent.name .. " " .. extra_info_for_scan_list(ent.ent,pindex,true) .. ", " .. description, pindex)
      else
         printout("Missing " .. ent.name .. " " .. description, pindex)
      end
   elseif direction == adjusted[(2 + dir)%8] or direction == adjusted[(6 + dir) %8] then
      if (dir == 0 or dir == 6) and index > 1 then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].structure_travel.index = index - 1
      elseif (dir == 2 or dir == 4) and index < #network[current][direction] then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].structure_travel.index = index + 1
      end
      local index = players[pindex].structure_travel.index
      local dx = network[current][direction][index].dx
      local dy = network[current][direction][index].dy
      local description = ""
      if math.floor(math.abs(dx)+ .5) ~= 0 then
         if dx < 0 then
            description = description .. math.floor(math.abs(dx)+.5) .. " " .. "tiles west, "
         elseif dx > 0 then
            description = description .. math.floor(math.abs(dx)+.5) .. " " .. "tiles east, "
         end
      end
      if math.floor(math.abs(dy)+ .5) ~= 0 then
         if dy < 0 then
            description = description .. math.floor(math.abs(dy)+.5) .. " " .. "tiles north, "
         elseif dy > 0 then
            description = description .. math.floor(math.abs(dy)+.5) .. " " .. "tiles south, "
         end
      end
      local ent = network[network[current][direction][index].num]
      if ent.ent.valid then
         move_cursor_map(ent.ent.position,pindex)
         players[pindex].cursor_pos = ent.ent.position
         --Case 4: Propose a new structure within the same direction
         printout("To " .. ent.name .. " " .. extra_info_for_scan_list(ent.ent,pindex,true) .. ", " .. description  .. ", " .. index .. " of " .. #network[current][direction], pindex)
      else
         printout("Missing " .. ent.name .. " " .. description, pindex)
      end
   end
end

--Usually called when the cursor find an entity, gives its name and key information.
function ent_info(pindex, ent, description)
   local result = ent.name
   if game.players[pindex].name == "Crimso" then
      result = result .. " " .. ent.type .. " "
   end
   if game.get_player(pindex).driving then--Note: this is also checked in read_tile
      result = result .. ", cannot check details while driving. "
      return result
   end
   if ent.type == "resource" then
      result = result .. ", x " .. ent.amount
   end
   if ent.name == "entity-ghost" then
      result = result .. " for a " .. ent.ghost_name .. ", "
   elseif ent.name == "straight-rail" or ent.name == "curved-rail" then
      return rail_ent_info(pindex, ent, description)
   end

   result = result .. (description or "")
   
   --Give character names
   if ent.name == "character" then
      local p = ent.player
      local p2 = ent.associated_player
      if p ~= nil and p.valid and p.name ~= nil and p.name ~= "" then
         result = result .. " " .. p.name 
      elseif p2 ~= nil and p2.valid and p2.name ~= nil and p2.name ~= "" then
         result = result .. " " .. p2.name 
      elseif p ~= nil and p.valid and p.index == pindex then
         result = result .. " you "
      elseif pindex ~= nil then
         result = result .. " " .. pindex
      else
         result = result .. " X "
      end
      
      if p ~= nil and p.valid and p.index == pindex and not players[pindex].cursor then
         return ""
      end
      
   elseif ent.name == "character-corpse" then
      if ent.character_corpse_player_index == pindex then
         result = result .. " of your character "
      elseif ent.character_corpse_player_index ~= nil then
         result = result .. " of another character "
      end
   end
   --Explain the contents of a container
   if ent.type == "container" or ent.type == "logistic-container" then --Chests etc: Report the most common item and say "and other items" if there are other types.
      local itemset = ent.get_inventory(defines.inventory.chest).get_contents()
      local itemtable = {}
      for name, count in pairs(itemset) do
         table.insert(itemtable, {name = name, count = count})
      end
      table.sort(itemtable, function(k1, k2)
         return k1.count > k2.count
      end)
      if #itemtable == 0 then
         result = result .. " containing nothing "
      else
         result = result .. " containing " .. itemtable[1].name .. " times " .. itemtable[1].count .. ", "
         if #itemtable > 1 then
            result = result .. " and " .. itemtable[2].name .. " times " .. itemtable[2].count .. ", "
         end
         if #itemtable > 2 then
            result = result .. "and other items "
         end
      end
      
   end  
   --Explain the contents of a pipe or storage tank or etc.
   if ent.type == "pipe" or ent.type == "pipe-to-ground" or ent.type == "storage-tank" or ent.type == "pump" or ent.name == "boiler" or ent.name == "heat-exchanger" then
      local dict = ent.get_fluid_contents()
      local fluids = {}
      for name, count in pairs(dict) do
         table.insert(fluids, {name = name, count = count})
      end
      table.sort(fluids, function(k1, k2)
         return k1.count > k2.count
      end)
      if #fluids > 0 and fluids[1].count ~= nil then
         result = result .. " containing " .. fluids[1].name .. " times " .. math.ceil(fluids[1].count) .. ", "
		 if #fluids > 1 and fluids[2].count ~= nil then
            result = result .. " and " .. fluids[2].name .. " times " .. math.ceil(fluids[2].count) .. ", "
		 end
		 if #fluids > 2 then
            result = result .. ", and other fluids "
		 end
      else
      result = result .. " containing no fluid "
      end
   end
   --Explain the type and content of a transport belt
   if ent.type == "transport-belt" then
      --Check if corner or junction or end
      local sideload_count = 0
      local backload_count = 0
      local outload_count = 0
      local inputs = ent.belt_neighbours["inputs"]
      local outputs = ent.belt_neighbours["outputs"]
      local outload_dir = nil
      local this_dir = ent.direction
      for i, belt in pairs(inputs) do
         if ent.direction ~= belt.direction then
            sideload_count = sideload_count + 1
         else
            backload_count = backload_count + 1
         end
      end
      for i, belt in pairs(outputs) do
         outload_count = outload_count + 1
         outload_dir = belt.direction--Note: there should be only one of these belts anyway.
      end
      --Check what the neighbor info reveals about the belt
      result = result .. transport_belt_junction_info(sideload_count, backload_count, outload_count, this_dir, outload_dir)
      
      --Check contents
      local left = ent.get_transport_line(1).get_contents()
      local right = ent.get_transport_line(2).get_contents()

      for name, count in pairs(right) do
         if left[name] ~= nil then
            left[name] = left[name] + count
         else
            left[name] = count
         end
      end
      local contents = {}
      for name, count in pairs(left) do
         table.insert(contents, {name = name, count = count})
      end
      table.sort(contents, function(k1, k2)
         return k1.count > k2.count
      end)
      if #contents > 0 then
         result = result .. " carrying " .. contents[1].name
         if #contents > 1 then
            result = result .. ", and " .. contents[2].name
            if #contents > 2 then
               result = result .. ", and other item types " 
            end
         end

      else
         --No currently carried items: Now try to announce likely recently carried items by checking the next belt over (must have only this belt as input)
         local next_belt = ent.belt_neighbours["outputs"][1]
          --Check contents
         local next_contents = {}
         if next_belt ~= nil and next_belt.valid and #next_belt.belt_neighbours["inputs"] == 1 then
            local left = next_belt.get_transport_line(1).get_contents()
            local right = next_belt.get_transport_line(2).get_contents()

            for name, count in pairs(right) do
               if left[name] ~= nil then
                  left[name] = left[name] + count
               else
                  left[name] = count
               end
            end
            for name, count in pairs(left) do
               table.insert(next_contents, {name = name, count = count})
            end
            table.sort(next_contents, function(k1, k2)
               return k1.count > k2.count
            end)
         end
         
         if #next_contents > 0 then
            result = result .. " assumed carrying " .. next_contents[1].name
            if #next_contents > 1 then
               result = result .. ", and " .. next_contents[2].name
               if #next_contents > 2 then
                  result = result .. ", and other item types " 
               end
            end
         else
            --No currently or recently carried items
            result = result ..  " carrying nothing, "
         end
      end
   end
   
   --For underground belts, note whether entrance or Exited
   if ent.type == "underground-belt" then
      if ent.belt_to_ground_type == "input" then
	     result = result .. " entrance "
	  elseif ent.belt_to_ground_type == "output" then
	     result = result .. " exit "
	  end
   end
   
   --Explain the recipe of a machine without pause and before the direction
   pcall(function()
      if ent.get_recipe() ~= nil then
         result = result .. " producing " .. ent.get_recipe().name
      end
   end)
   
   --State the name of a train stop
   if ent.name == "train-stop" then
      result = result .. " " .. ent.backer_name .. " "
   --State the ID number of a train
   elseif ent.name == "locomotive" or ent.name == "cargo-wagon" or ent.name == "fluid-wagon" then
      result = result .. " of train " .. get_train_name(ent.train)
   end

   --Explain the entity facing direction
   if ent.prototype.is_building and ent.supports_direction then
      result = result .. ", Facing "
      if ent.direction == 0 then 
         result = result .. "North "
      elseif ent.direction == 1 then
         result = result .. "Northeast "
      elseif ent.direction == 2 then
         result = result .. "East "
      elseif ent.direction == 3 then
         result = result .. "Southeast "
      elseif ent.direction == 4 then
         result = result .. "South "
      elseif ent.direction == 5 then
         result = result .. "Southwest "
      elseif ent.direction == 6 then
         result = result .. "West "
      elseif ent.direction == 7 then
         result = result .. "Northwest "
      end
   elseif ent.name == "locomotive" or ent.prototype.type == "car" then
      result = result .. " facing " .. get_heading(ent)
   end
   if ent.prototype.type == "generator" then
      result = result .. ", "
      local power1 = ent.energy_generated_last_tick * 60
      local power2 = ent.prototype.max_energy_production * 60
      if power2 ~= nil then
         result = result .. "Producing " .. get_power_string(power1) .. " out of " .. get_power_string(power2) .. " capacity, "
      else
         result = result .. "Producing " .. get_power_string(power1) .. " "
      end
   end
   if ent.type == "underground-belt" then
      if ent.neighbours ~= nil then
         result = result .. ", Connected to " .. direction(ent.position, ent.neighbours.position) .. " via " .. math.floor(distance(ent.position, ent.neighbours.position)) - 1 .. " tiles underground, "
      else
         result = result .. ", not connected " 
      end
   elseif (ent.name  == "pipe") and ent.neighbours ~= nil then
      result = result .. ", connected to "
      for i, v in pairs(ent.neighbours) do
         for i1, v1 in pairs(v) do
            result = result .. ", " .. math.floor(distance(ent.position, v1.position)) .. " " .. direction(ent.position, v1.position)
         end
      end
   elseif (ent.name == "pipe-to-ground") and ent.neighbours ~= nil then
      result = result .. ", connected to "
      local connections = ent.fluidbox.get_pipe_connections(1)
      local at_least_one = false
      for i,con in ipairs(connections) do
         if con.target ~= nil then
            local dist = math.ceil(util.distance(ent.position,con.target.get_pipe_connections(1)[1].position))
            result = result .. direction_lookup(get_direction_of_that_from_this(con.target_position,ent.position)) .. " "
            if con.connection_type == "underground" then
               result = result .. " via " .. dist - 1 .. " tiles underground, "
            else
               result = result .. " by " .. dist .. " tiles, "
            end
            result = result .. ", "
            at_least_one = true
         end
      end
      if not at_least_one then
         result = result .. " nothing "
      end
   elseif next(ent.prototype.fluidbox_prototypes) ~= nil then
      local relative_position = {x = players[pindex].cursor_pos.x - ent.position.x, y = players[pindex].cursor_pos.y - ent.position.y}
      local direction = ent.direction/2
      local inputs = 0
      for i, box in pairs(ent.prototype.fluidbox_prototypes) do
         for i1, pipe in pairs(box.pipe_connections) do
            if pipe.type == "input" then
               inputs = inputs + 1
            end
            local adjusted = {position, direction}
            if ent.name == "offshore-pump" then
               adjusted.position = {x = 0, y = 0}
               if direction == 0 then 
                  adjusted.direction = "South"
               elseif direction == 1 then 
                  adjusted.direction = "West"
               elseif direction == 2 then 
                  adjusted.direction = "North"
               elseif direction == 3 then 
                  adjusted.direction = "East"
               end
            else
               adjusted = get_adjacent_source(ent.prototype.selection_box, pipe.positions[direction + 1], direction)
            end
            if adjusted.position.x == relative_position.x and adjusted.position.y == relative_position.y then
               if ent.type == "assembling-machine" and ent.get_recipe() ~= nil then
                  if ent.name == "oil-refinery" and ent.get_recipe().name == "basic-oil-processing" then
                     if i == 2 then
                        result = result .. ", crude-oil Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
                     elseif i == 5 then
                        result = result .. ", petroleum-gas Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
                     else
                        result = result .. ", " .. "Unused" .. " Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
                     end
                  else
                     if pipe.type == "input" then
                        local inputs = ent.get_recipe().ingredients
                        for i2 = #inputs, 1, -1 do
                           if inputs[i2].type ~= "fluid" then
                              table.remove(inputs, i2)
                           end
                        end
                        if #inputs > 0 then
                           local i3 = (i%#inputs)
                           if i3 == 0 then
                              i3 = #inputs
                           end
                           local filter = inputs[i3]
                           result = result .. ", " .. filter.name .. " Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
                        else
                           result = result .. ", " .. "Unused" .. " Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
                        end
                     else
                        local outputs = ent.get_recipe().products
                        for i2 = #outputs, 1, -1 do
                           if outputs[i2].type ~= "fluid" then
                              table.remove(outputs, i2)
                           end
                        end
                        if #outputs > 0 then
                           local i3 = ((i-inputs)%#outputs)
                           if i3 == 0 then
                              i3 = #outputs
                           end
                           local filter = outputs[i3]
                           result = result .. ", " .. filter.name .. " Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
                        else
                           result = result .. ", " .. "Unused" .. " Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
                        end

                     end
                  end

               else
                  local filter = box.filter or {name = ""}
                  result = result .. ", " .. filter.name .. " Flow " .. pipe.type .. " 1 " .. adjusted.direction .. ", at " .. get_entity_part_at_cursor(pindex)
               end
            end
         end
      end
   end
   
   if ent.type == "transport-belt" then
      --Check whether items on the belt are stopped or moving (based on whether you can insert at the back of the belt)
      local left = ent.get_transport_line(1)
      local right = ent.get_transport_line(2)
      
      local left_dir = "left"
      local right_dir = "right"
      if ent.direction == dirs.north then
         left_dir = direction_lookup(dirs.west)
         right_dir = direction_lookup(dirs.east)
      elseif ent.direction == dirs.east then
         left_dir = direction_lookup(dirs.north)
         right_dir = direction_lookup(dirs.south)
      elseif ent.direction == dirs.south then
         left_dir = direction_lookup(dirs.east)
         right_dir = direction_lookup(dirs.west)
      elseif ent.direction == dirs.west then
         left_dir = direction_lookup(dirs.south)
         right_dir = direction_lookup(dirs.north)
      end
      
      local insert_spots_left = 0
      local insert_spots_right = 0
      if not left.can_insert_at_back() and right.can_insert_at_back() then
         result = result .. ", " ..  left_dir .. " lane full and stopped, "
      elseif left.can_insert_at_back() and not right.can_insert_at_back() then
         result = result .. ", " ..  right_dir .. " lane full and stopped, "
      elseif not left.can_insert_at_back() and not right.can_insert_at_back() then
         result = result ..  ", both lanes full and stopped, "
         --game.get_player(pindex).print(", both lanes full and stopped, ")
      else
         result = result .. ", both lanes open, "
         --game.get_player(pindex).print(", both lanes open, ")
      end
   elseif ent.name == "cargo-wagon" then
      --Explain contents
      local itemset = ent.get_inventory(defines.inventory.cargo_wagon).get_contents()
      local itemtable = {}
      for name, count in pairs(itemset) do
         table.insert(itemtable, {name = name, count = count})
      end
      table.sort(itemtable, function(k1, k2)
         return k1.count > k2.count
      end)
      if #itemtable == 0 then
         result = result .. " containing nothing "
      else
         result = result .. " containing " .. itemtable[1].name .. " times " .. itemtable[1].count .. ", "
         if #itemtable > 1 then
            result = result .. " and " .. itemtable[2].name .. " times " .. itemtable[2].count .. ", "
         end
         if #itemtable > 2 then
            result = result .. "and other items "
         end
      end
   elseif ent.type == "electric-pole" then
      --List connected electric poles
      if #ent.neighbours.copper == 0 then
         result = result .. " with no connections, "
      else
         result = result .. " connected to "
         for i,pole in ipairs(ent.neighbours.copper) do
            local dir = get_direction_of_that_from_this(pole.position,ent.position)
            local dist = util.distance(pole.position,ent.position)
            if i > 1 then
               result = result .. " and "
            end
            result = result .. math.ceil(dist) .. " tiles " .. direction_lookup(dir) .. ", "
         end
      end
      --Count number of entities being supplied within supply area.
      local pos = ent.position
      local sdist = ent.prototype.supply_area_distance
      local supply_area = {{pos.x - sdist, pos.y - sdist}, {pos.x + sdist, pos.y + sdist}}
      local supplied_ents = ent.surface.find_entities_filtered{area = supply_area}
      local supplied_count = 0
      local producer_count = 0
      for i, ent2 in ipairs(supplied_ents) do
         if ent2.prototype.max_energy_usage ~= nil and ent2.prototype.max_energy_usage > 0 then
            supplied_count = supplied_count + 1
         elseif ent2.prototype.max_energy_production ~= nil and ent2.prototype.max_energy_production > 0 then
            producer_count = producer_count + 1
         end
      end
      result = result .. " supplying " .. supplied_count .. " buildings, " 
      if producer_count > 0 then
         result = result .. " drawing from " .. producer_count .. " buildings, " 
      end
      result = result .. "Check status for power flow information. "
      
   elseif ent.name == "rail-signal" or ent.name == "rail-chain-signal" then
      result = result .. ", " .. get_signal_state_info(ent)
   elseif ent.name == "roboport" then
      local cell = ent.logistic_cell
      local network = ent.logistic_cell.logistic_network
      result = result .. " of network " .. get_network_name(ent) .. "," .. roboport_contents_info(ent)
   end
   --Give drop position (like for inserters)
   if ent.drop_position ~= nil then
      --Also for inserters, announce if they are holding something
      if ent.type == "inserter" and ent.held_stack ~= nil and ent.held_stack.valid_for_read and ent.held_stack.valid then
         result = result .. ", holding " .. ent.held_stack.name
         if ent.held_stack.count > 1 then
            result = result .. " times " .. ent.held_stack.count
         end
      elseif ent.type == "inserter" and (ent.held_stack == nil) then 
         result = result .. ", holding nothing "
      end
      --Next explain drop position
      local position = table.deepcopy(ent.drop_position)
      local direction = ent.direction /2
      local increment = 1
      if ent.type == "inserter" then
         direction = (direction + 2) % 4
         if ent.name == "long-handed-inserter" then
            increment = 2
         end
      end
      if direction == 0 then
         position.y = position.y + increment
      elseif direction == 2 then
         position.y = position.y - increment
      elseif direction == 3 then
         position.x = position.x + increment
      elseif direction == 1 then
         position.x = position.x - increment
      end
--         result = result .. math.floor(position.x) .. " " .. math.floor(position.y) .. " " .. direction .. " "
      if math.floor(players[pindex].cursor_pos.x) == math.floor(position.x) and math.floor(players[pindex].cursor_pos.y) == math.floor(position.y) then
         result = result .. ", Output " .. increment .. " "
         if direction == 0 then
            result = result .. "North "
         elseif direction == 2 then
            result = result .. "South "
         elseif direction == 3 then
            result = result .. "West " 
         elseif direction == 1 then
            result = result .. "East "
         end
      end
   end
   if ent.type == "mining-drill"  then
      local pos = ent.position
      local radius = ent.prototype.mining_drill_radius
      local area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}
      local resources = ent.surface.find_entities_filtered{area = area, type = "resource"}
      local dict = {}
      for i, resource in pairs(resources) do
         if dict[resource.name] == nil then
            dict[resource.name] = resource.amount
         else
            dict[resource.name] = dict[resource.name] + resource.amount
         end
      end
      if table_size(dict) > 0 then
         result = result .. ", Mining From "
         for i, amount in pairs(dict) do
            result = result .. " " .. i .. " x " .. amount
         end
      end
   end
   
   if ent.prototype.burner_prototype ~= nil then
      if ent.energy == 0 and fuel_inventory_info(ent) == "Contains no fuel." then
         result = result .. ", Out of Fuel "
      end
   end

   if ent.prototype.electric_energy_source_prototype ~= nil and ent.is_connected_to_electric_network() == false then
      result = result .. " Not Connected"
   elseif ent.prototype.electric_energy_source_prototype ~= nil and ent.energy == 0 and ent.type ~= "solar-panel" then
      result = result .. " Connected but no power "
   end
   if ent.type == "accumulator" then
      local level = math.ceil(ent.energy / 50000) --In percentage
      local charge = math.ceil(ent.energy / 1000) --In kilojoules
      result = result .. ", " .. level .. " percent full, containing " .. charge .. " kilojoules. "
   elseif ent.type == "solar-panel" then
      local s_time = ent.surface.daytime*24 --We observed 18 = peak solar start, 6 = peak solar end, 11 = night start, 13 = night end
      local solar_status = ""
      if s_time > 13 and s_time <= 18 then
         solar_status = ", increasing production, morning hours. "
      elseif s_time > 18 or s_time < 6 then
         solar_status = ", full production, day time. "
      elseif s_time > 6 and s_time <= 11 then
         solar_status = ", decreasing production, evening hours. "
      elseif s_time > 11 and s_time <= 13 then
         solar_status = ", zero production, night time. "
      end
      result = result .. solar_status
   elseif ent.name == "rocket-silo" then
      if ent.rocket_parts ~= nil and ent.rocket_parts < 100 then
	     result = result .. ", " .. ent.rocket_parts .. " finished out of 100. "
	  elseif ent.rocket_parts ~= nil then
         result = result .. ", rocket ready, press SPACE to launch. "
	  end
   elseif ent.name == "beacon" then
      local modules = ent.get_module_inventory()
	  if modules.get_item_count() == 0 then
	     result = result .. " with no modules "
	  elseif modules.get_item_count() == 1 then
	     result = result .. " with " .. modules[1].name
	  elseif modules.get_item_count() == 2 then
	     result = result .. " with " .. modules[1].name .. " and " .. modules[2].name
      elseif modules.get_item_count() > 2 then
	     result = result .. " with " .. modules[1].name .. " and " .. modules[2].name .. " and other modules "
      end
   elseif ent.name == "nuclear-reactor" or ent.name == "heat-pipe" or ent.name == "heat-exchanger" then
      result = result .. ", temperature " .. math.floor(ent.temperature) .. " degrees C "
	  if ent.name == "nuclear-reactor" then
	     if ent.temperature > 900 then
	        result = result .. ", danger "
		 end
		 if ent.energy > 0 then
	        result = result .. ", consuming fuel cell "
		 end
	     result = result .. ", neighbour bonus " .. ent.neighbour_bonus * 100 .. " percent "
	  end
   elseif ent.name == "item-on-ground" then
      result = result .. ", " .. ent.stack.name 
   end
   return result
end

--Explain whether the belt is some type of corner or sideloading junction or etc.
function transport_belt_junction_info(sideload_count, backload_count, outload_count, this_dir, outload_dir, say_middle)
   local say_middle = say_middle or false
   local result = ""
   if     sideload_count == 0 and backload_count == 0 and outload_count == 0 then
      result = result .. " unit "
   elseif sideload_count == 0 and backload_count == 1 and outload_count == 0 then
      result = result .. " stopping end "
   elseif sideload_count == 1 and backload_count == 0 and outload_count == 0 then
      result = result .. " stopping end corner "
   elseif sideload_count == 1 and backload_count == 1 and outload_count == 0 then
      result = result .. " sideloading stopping end "
   elseif sideload_count == 2 and backload_count == 1 and outload_count == 0 then
      result = result .. " double sideloading stopping end "
   elseif sideload_count == 2 and backload_count == 0 and outload_count == 0 then
      result = result .. " safe merging stopping end "
   elseif sideload_count == 0 and backload_count == 0 and outload_count == 1 and this_dir == outload_dir then
      result = result .. " start "
   elseif sideload_count == 0 and backload_count == 1 and outload_count == 1 and this_dir == outload_dir then
      if say_middle then
         result = result .. " middle "
      else
         result = result .. " " 
      end
   elseif sideload_count == 1 and backload_count == 0 and outload_count == 1 and this_dir == outload_dir then
      result = result .. " corner "
   elseif sideload_count == 1 and backload_count == 1 and outload_count == 1 and this_dir == outload_dir then
      result = result .. " sideloading junction "
   elseif sideload_count == 2 and backload_count == 1 and outload_count == 1 and this_dir == outload_dir then
      result = result .. " double sideloading junction "
   elseif sideload_count == 2 and backload_count == 0 and outload_count == 1 and this_dir == outload_dir then
      result = result .. " safe merging junction "
   elseif sideload_count == 0 and backload_count == 0 and outload_count == 1 and this_dir ~= outload_dir then
      result = result .. " unit pouring end "
   elseif sideload_count == 0 and backload_count == 1 and outload_count == 1 and this_dir ~= outload_dir then
      result = result .. " pouring end "
   elseif sideload_count == 1 and backload_count == 0 and outload_count == 1 and this_dir ~= outload_dir then
      result = result .. " corner pouring end "
   elseif sideload_count == 1 and backload_count == 1 and outload_count == 1 and this_dir ~= outload_dir then
      result = result .. " sideloading pouring end "
   elseif sideload_count == 2 and backload_count == 1 and outload_count == 1 and this_dir ~= outload_dir then
      result = result .. " double sideloading pouring end "
   elseif sideload_count == 2 and backload_count == 0 and outload_count == 1 and this_dir ~= outload_dir then
      result = result .. " safe merging pouring end "
   elseif sideload_count + backload_count > 1 and (outload_count == 0 or (outload_count == 1 and this_dir == outload_dir)) then
      result = result .. " unidentified junction "--this should not be reachable any more
   elseif sideload_count + backload_count > 1 and outload_count == 1 and this_dir ~= outload_dir then
      result = result .. " unidentified pouring end "
   elseif outload_count > 1 then
      result = result .. " multiple outputs " --unexpected case
   else
      result = result .. " unknown state " --unexpected case
   end
   return result
   --Note: A pouring end either pours into a sideloading junction, or into a corner. Lanes are preserved if the target is a corner.
end

--Creates the building network that is traveled during structure travel. 
function compile_building_network(ent, radius_in,pindex)--**Todo bug: Some neighboring structures are not picked up when they should be such as machines next to inserters
   local radius = radius_in
   local ents = ent.surface.find_entities_filtered{position = ent.position, radius = radius}
   game.get_player(pindex).print(#ents .. " ents at first pass")
   if #ents < 100 then
      radius = radius_in * 2
      ents = ent.surface.find_entities_filtered{position = ent.position, radius = radius}
   elseif #ents > 2000 then
      radius = math.floor(radius_in/4)
      ents = ent.surface.find_entities_filtered{position = ent.position, radius = radius}
   elseif #ents > 1000 then
      radius = math.floor(radius_in/2)
      ents = ent.surface.find_entities_filtered{position = ent.position, radius = radius}
   end
   rendering.draw_circle{color = {1, 1, 1},radius = radius,width = 20,target = ent.position, surface = ent.surface, draw_on_ground = true, time_to_live = 300}
   --game.get_player(pindex).print(#ents .. " ents at start")
   local adj = {hor = {}, vert = {}}
   local PQ = {}
   local result = {}
   --game.get_player(pindex).print("checkpoint 0")
   table.insert(ents, 1, ent)
   for i = #ents, 1, -1 do
      local row = ents[i]
      if row.unit_number ~= nil and (row.prototype.is_building or row.unit_number == ent.unit_number) then
         adj.hor[row.unit_number] = {}
         adj.vert[row.unit_number] = {}
         result[row.unit_number] = {
            ent = row,
            name = row.name,
            position = table.deepcopy(row.position),
            north = {},
            east = {},
            south = {},
            west = {}
         }
      else
         table.remove(ents, i)
      end
   end
   
   game.get_player(pindex).print(#ents .. " buildings found")--**keep here intentionally
   --game.get_player(pindex).print("checkpoint 1")
   
   for i, row in pairs(ents) do
      for i1, col in pairs(ents) do
         if adj.hor[row.unit_number][col.unit_number] == nil then
            if row.unit_number == col.unit_number then
               adj.hor[row.unit_number][col.unit_number] = true
               adj.vert[row.unit_number][col.unit_number] = true
            else
               adj.hor[row.unit_number][col.unit_number] = false
               adj.vert[row.unit_number][col.unit_number] = false
               adj.hor[col.unit_number][row.unit_number] = false
               adj.vert[col.unit_number][row.unit_number] = false

               table.insert(PQ, {
                  source = row,
                  dest = col,
                  dx = col.position.x - row.position.x,
                  dy = col.position.y - row.position.y,
                  man = math.abs(col.position.x - row.position.x) + math.abs(col.position.y - row.position.y)
               })
               
            end
         end
      
      end
   end
   --game.get_player(pindex).print("checkpoint 2")
   table.sort(PQ, function (k1, k2)
      return k1.man > k2.man
   end)
   --game.get_player(pindex).print("checkpoint 3, #PQ = " .. #PQ)--
   
   local entry = table.remove(PQ)
   local loop_count = 0
   while entry~= nil and loop_count < #PQ * 2 do
      loop_count = loop_count + 1
      if math.abs(entry.dy) >= math.abs(entry.dx) then
         if not adj.vert[entry.source.unit_number][entry.dest.unit_number] then
            for i, explored in pairs(adj.vert[entry.source.unit_number]) do
               adj.vert[entry.source.unit_number][i] = (explored or adj.vert[entry.dest.unit_number][i])
            end
         for i, row in pairs(adj.vert) do
            if adj.vert[entry.source.unit_number][i] then
               adj.vert[i] = adj.vert[entry.source.unit_number]
            end
         end
            if entry.dy > 0 then
    
               table.insert(result[entry.source.unit_number].south, {
                  num = entry.dest.unit_number,
                  dx = entry.dx,
                  dy = entry.dy
               })
               table.insert(result[entry.dest.unit_number].north, {
                  num = entry.source.unit_number,
                  dx = entry.dx * -1,
                  dy = entry.dy * -1
               })
            else
               table.insert(result[entry.source.unit_number].north, {
                  num = entry.dest.unit_number,
                  dx = entry.dx,
                  dy = entry.dy
               })
               table.insert(result[entry.dest.unit_number].south, {
                  num = entry.source.unit_number,
                  dx = entry.dx * -1,
                  dy = entry.dy * -1
               })

            end
         end
      end
      if math.abs(entry.dx) >= math.abs(entry.dy) then
         if not adj.hor[entry.source.unit_number][entry.dest.unit_number] then
            for i, explored in pairs(adj.hor[entry.source.unit_number]) do
               adj.hor[entry.source.unit_number][i] = explored or adj.hor[entry.dest.unit_number][i]
            end
         for i, row in pairs(adj.hor) do
            if adj.hor[entry.source.unit_number][i] then
               adj.hor[i] = adj.hor[entry.source.unit_number]
            end
         end
            if entry.dx > 0 then
               table.insert(result[entry.source.unit_number].east, {
                  num = entry.dest.unit_number,
                  dx = entry.dx,
                  dy = entry.dy
               })
               table.insert(result[entry.dest.unit_number].west, {
                  num = entry.source.unit_number,
                  dx = entry.dx * -1,
                  dy = entry.dy * -1
               })
            else
               table.insert(result[entry.source.unit_number].west, {
                  num = entry.dest.unit_number,
                  dx = entry.dx,
                  dy = entry.dy
               })
               table.insert(result[entry.dest.unit_number].east, {
                  num = entry.source.unit_number,
                  dx = entry.dx * -1,
                  dy = entry.dy * -1
               })

            end
         end

      end
      entry = table.remove(PQ)
   end
   --game.get_player(pindex).print("checkpoint 4, loop count: " .. loop_count )
   return result
end   

function read_travel_slot(pindex)
   if #global.players[pindex].travel == 0 then
      printout("Move towards the right and select Create to get started.", pindex)
   else
      local entry = global.players[pindex].travel[players[pindex].travel.index.y]
      printout(entry.name .. " at " .. math.floor(entry.position.x) .. ", " .. math.floor(entry.position.y), pindex)
      players[pindex].cursor_pos = center_of_tile(entry.position)
      cursor_highlight(pindex, nil, "train-visualization")
   end
end

--Makes the player teleport to the closest valid position to a target position. Uses game's teleport function. Muted makes silent and effectless teleporting
function teleport_to_closest(pindex, pos, muted, ignore_enemies)
   local pos = table.deepcopy(pos)
   local muted = muted or false
   local first_player = game.get_player(pindex)
   local surf = first_player.surface
   local radius = .5
   local new_pos = surf.find_non_colliding_position("character", pos, radius, .1, true)
   while new_pos == nil do
      radius = radius + 1 
      new_pos = surf.find_non_colliding_position("character", pos, radius, .1, true)
   end
   --Do not teleport if in a vehicle, in a menu, or already at the desitination
   if first_player.vehicle ~= nil and first_player.vehicle.valid then
      printout("Cannot teleport while in a vehicle.", pindex)
      return false
   elseif util.distance(game.get_player(pindex).position, pos) <= 1.5 then 
      printout("Already at target", pindex)
      return false
   elseif players[pindex].in_menu and players[pindex].menu ~= "travel" then
      printout("Cannot teleport while in a menu.", pindex)
      return false
   end
   --Do not teleport near enemies unless instructed to ignore them
   if not ignore_enemies then
      local enemy = first_player.surface.find_nearest_enemy{position = new_pos, max_distance = 30, force =  first_player.force}
      if enemy and enemy.valid then
         printout("Warning: There are enemies at this location, but you can force teleporting if you press CONTROL + SHIFT + T", pindex)
         return false
      end
   end
   --Attempt teleport
   local can_port = first_player.surface.can_place_entity{name = "character", position = new_pos} 
   if can_port then
      local old_pos = table.deepcopy(first_player.position)
      if not muted then
         --Teleporting visuals at origin
         rendering.draw_circle{color = {0.8, 0.2, 0.0},radius = 0.5,width = 15,target = old_pos, surface = first_player.surface, draw_on_ground = true, time_to_live = 60}
         rendering.draw_circle{color = {0.6, 0.1, 0.1},radius = 0.3,width = 20,target = old_pos, surface = first_player.surface, draw_on_ground = true, time_to_live = 60}
         local smoke_effect = first_player.surface.create_entity{name = "iron-chest", position = first_player.position, raise_built = false, force = first_player.force}
         smoke_effect.destroy{}
         --Teleport sound at origin
         game.get_player(pindex).play_sound{path = "player-teleported", volume_modifier = 0.2, position = old_pos}
         game.get_player(pindex).play_sound{path = "utility/scenario_message", volume_modifier = 0.8, position = old_pos}
      end
      local teleported = false 
      if muted then 
         teleported = first_player.teleport(new_pos)
      else
         teleported = first_player.teleport(new_pos)
      end
      if teleported then
         first_player.force.chart(first_player.surface, {{new_pos.x-15,new_pos.y-15},{new_pos.x+15,new_pos.y+15}})
         players[pindex].position = table.deepcopy(new_pos)
         reset_bump_stats(pindex)
         if not muted then
            --Teleporting visuals at target
            rendering.draw_circle{color = {0.3, 0.3, 0.9},radius = 0.5,width = 15,target = new_pos, surface = first_player.surface, draw_on_ground = true, time_to_live = 60}
            rendering.draw_circle{color = {0.0, 0.0, 0.9},radius = 0.3,width = 20,target = new_pos, surface = first_player.surface, draw_on_ground = true, time_to_live = 60}
            local smoke_effect = first_player.surface.create_entity{name = "iron-chest", position = first_player.position, raise_built = false, force = first_player.force}
            smoke_effect.destroy{}
            --Teleport sound at target
            game.get_player(pindex).play_sound{path = "player-teleported", volume_modifier = 0.2, position = new_pos}
            game.get_player(pindex).play_sound{path = "utility/scenario_message", volume_modifier = 0.8, position = new_pos}
         end
         if new_pos.x ~= pos.x or new_pos.y ~= pos.y then
            if not muted then
               printout("Teleported " .. math.ceil(distance(pos,first_player.position)) .. " " .. direction(pos, first_player.position) .. " of target", pindex)
            end
         end        
         --Update cursor after teleport
         players[pindex].cursor_pos = table.deepcopy(new_pos)
         move_cursor_map(center_of_tile(players[pindex].cursor_pos),pindex)
         cursor_highlight(pindex,nil,nil)
      else
         printout("Teleport Failed", pindex)
         return false
      end
   else
      printout("Cannot teleport", pindex)--this is unlikely to be reached because we find the first non-colliding position
      return false
   end
   return true
end

function read_warnings_slot(pindex)
   local warnings = {}
   if players[pindex].warnings.sector == 1 then
      warnings = players[pindex].warnings.short.warnings
   elseif players[pindex].warnings.sector == 2 then
      warnings = players[pindex].warnings.medium.warnings
   elseif players[pindex].warnings.sector == 3 then
      warnings= players[pindex].warnings.long.warnings
   end
   if players[pindex].warnings.category <= #warnings and players[pindex].warnings.index <= #warnings[players[pindex].warnings.category].ents then
      local ent = warnings[players[pindex].warnings.category].ents[players[pindex].warnings.index]
      if ent ~= nil and ent.valid then
         printout(ent.name .. " has " .. warnings[players[pindex].warnings.category].name .. " at " .. math.floor(ent.position.x) .. ", " .. math.floor(ent.position.y), pindex)
      else
         printout("Blank", pindex)
      end
   else
      printout("No warnings for this range.  Press tab to pick a larger range, or press E to close this menu.", pindex)
   end
end

function get_line_items(network)
   local result = {combined = {left = {}, right = {}}, downstream = {left = {}, right = {}}, upstream = {left = {}, right = {}}}
   local dict = {}
   for i, line in pairs(network.downstream.left) do
      for name, count in pairs(line.get_contents()) do
         if dict[name] == nil then
            dict[name] = count
         else
            dict[name] = dict[name] + count
         end
      end
   end
   local total = table_size(network.downstream.left) * 4
   for name, count in pairs(dict) do
      table.insert(result.downstream.left, {name = name, count = count, percent = math.floor(1000* count/total)/10, valid = true, valid_for_read = true})
   end
   table.sort(result.downstream.left, function(k1, k2)
      return k1.percent > k2.percent
   end)

   local dict = {}
   for i, line in pairs(network.downstream.right) do
      for name, count in pairs(line.get_contents()) do
         if dict[name] == nil then
            dict[name] = count
         else
            dict[name] = dict[name] + count
         end
      end
   end
   local total = table_size(network.downstream.right) * 4
   for name, count in pairs(dict) do
      table.insert(result.downstream.right, {name = name, count = count, percent = math.floor(1000* count/total)/10, valid = true, valid_for_read = true})
   end
   table.sort(result.downstream.right, function(k1, k2)
      return k1.percent > k2.percent
   end)

   local dict = {}
   for i, line in pairs(network.upstream.left) do
      for name, count in pairs(line.get_contents()) do
         if dict[name] == nil then
            dict[name] = count
         else
            dict[name] = dict[name] + count
         end
      end
   end
   local total = table_size(network.upstream.left) * 4
   for name, count in pairs(dict) do
      table.insert(result.upstream.left, {name = name, count = count, percent = math.floor(1000* count/total)/10, valid = true, valid_for_read = true})
   end
   table.sort(result.upstream.left, function(k1, k2)
      return k1.percent > k2.percent
   end)

   local dict = {}
   for i, line in pairs(network.upstream.right) do
      for name, count in pairs(line.get_contents()) do
         if dict[name] == nil then
            dict[name] = count
         else
            dict[name] = dict[name] + count
         end
      end
   end
   local total = table_size(network.upstream.right) * 4
   for name, count in pairs(dict) do
      table.insert(result.upstream.right, {name = name, count = count, percent = math.floor(1000* count/total)/10, valid = true, valid_for_read = true})
   end
   table.sort(result.upstream.right, function(k1, k2)
      return k1.percent > k2.percent
   end)
   local dict = {}
   for i, item in pairs(result.downstream.left) do
   dict[item.name] = item.count
   end
   for i, item in pairs(result.upstream.left) do
      if dict[item.name] == nil then
         dict[item.name] = item.count
      else
         dict[item.name] = dict[item.name] + item.count
      end
   end

   local total = table_size(network.combined.left) * 4

   for name, count in pairs(dict) do
      table.insert(result.combined.left, {name = name, count = count, percent = math.floor(1000 * count/total) / 10, valid = true, valid_for_read = true})
   end
   table.sort(result.combined.left, function(k1, k2)
      return k1.percent > k2.percent
   end)

   local dict = {}
   for i, item in pairs(result.downstream.right) do
   dict[item.name] = item.count
   end
   for i, item in pairs(result.upstream.right) do
      if dict[item.name] == nil then
         dict[item.name] = item.count
      else
         dict[item.name] = dict[item.name] + item.count
      end
   end

   local total = table_size(network.combined.right) * 4

   for name, count in pairs(dict) do
      table.insert(result.combined.right, {name = name, count = count, percent = math.floor(1000 * count/total) / 10, valid = true, valid_for_read = true})
   end
   table.sort(result.combined.right, function(k1, k2)
      return k1.percent > k2.percent
   end)

   return result

end

function generate_production_network(pindex)
   local surf = game.get_player(pindex).surface
   local connectors = surf.find_entities_filtered{type="inserter"}
   local sources = surf.find_entities_filtered{type = "mining-drill"}
   local hash = {}
   local lines = {}
   local function explore_source(source)
      if hash[source.unit_number] == nil then
         hash[source.unit_number] = {
            production_line = math.huge,
            inputs = {},
            outputs = {},
            ent = source
         }
         local target = surf.find_entities_filtered{position = source.drop_position, type = production_types}[1]
         if target ~= nil then
            if target.type == "mining-drill" then
               table.insert(hash[source.unit_number].outputs, target.unit_number)
               explore_source(target)
               table.insert(hash[target.unit_number].inputs, source.unit_number)
               local new_line = math.min(hash[target.unit_number].production_line, table.maxn(lines) + 1)
               hash[source.unit_number].production_line = new_line
               lines[new_line] = lines[new_line] or {}
               table.insert(lines[new_line], source.unit_number)
            elseif target.type == "transport-belt" then
               if hash[target.unit_number] == nil then

                  local belts = get_connected_belts(target)
                  for i, belt in pairs(belts.hash) do
                     hash[i] = {link = target.unit_number}
                  end

                  local new_line = table.maxn(lines)+1
                  hash[target.unit_number] = {
                     production_line = new_line,
                     inputs = {source.unit_number},
                     outputs = {},
                     ent = target
                  }

                  hash[source.unit_number].production_line = new_line
                  lines[new_line] = {source.unit_number, target.unit_number}
               else
                  if hash[target.unit_number].link ~= nil then
                     hash[target.unit_number].ent = target
                     target = hash[hash[target.unit_number].link].ent
                  end
                  table.insert(hash[target.unit_number].inputs, source.unit_number)
                  table.insert(hash[source.unit_number].outputs, target.unit_number)
                  local new_line = hash[target.unit_number].production_line
                  hash[source.unit_number].production_line = new_line
   
                  table.insert(lines[new_line], source.unit_number)
               end
            else
               if hash[target.unit_number] == nil then
                  local new_line = table.maxn(lines)+1
                  hash[target.unit_number] = {
                     production_line = new_line,
                     inputs = {source.unit_number},
                     outputs = {},
                     ent = target
                  }
                  hash[source.unit_number].production_line = new_line
                  lines[new_line] = {source.unit_number, target.unit_number}
               else
                  table.insert(hash[target.unit_number].inputs, source.unit_number)
                  table.insert(hash[source.unit_number].outputs, target.unit_number)
                  hash[source.unit_number].production_line = hash[target.unit_number].production_line
                  table.insert(lines[hash[target.unit_number].production_line], source.unit_number)
               end
            end
         else
            local new_line = table.maxn(lines) + 1
            hash[source.unit_number].production_line = new_line
            lines[new_line] = {source.unit_number}
         end
      end
      end   
   for i, source in pairs(sources) do
      explore_source(source)
   end

   local function explore_connector(connector)
      if hash[connector.unit_number] == nil then
         hash[connector.unit_number] = {
            production_line = math.huge,
            inputs = {},
            outputs = {},
            ent = connector
         }
         local drop_target = surf.find_entities_filtered{position = connector.drop_position, type = production_types}[1]
         local pickup_target = surf.find_entities_filtered{position = connector.pickup_position, type = production_types}[1]
         if drop_target ~= nil then
            if drop_target.type == "inserter" then
               explore_connector(drop_target)
               local check = true
               for i, v in pairs(hash[drop_target.unit_number].inputs) do
                  if v == connector.unit_number then
                     check = false
                  end
               end
               if check then
                  table.insert(hash[drop_target.unit_number].inputs, connector.unit_number)
               end

               local check = true
               for i, v in pairs(hash[connector.unit_number].outputs) do
                  if v == drop_target.unit_number then
                     check = false
                  end
               end
               if check then
                  table.insert(hash[connector.unit_number].outputs, drop_target.unit_number)
               end
            elseif drop_target.type == "transport-belt" then
               if hash[drop_target.unit_number] == nil then
                  local belts = get_connected_belts(drop_target)
                  for i, belt in pairs(belts.hash) do
                     hash[i] = {link = drop_target.unit_number}
                  end

                  hash[drop_target.unit_number] = {
                     production_line = math.huge,
                     inputs = {connector.unit_number},
                     outputs = {},
                     ent = drop_target
                  }
                  table.insert(hash[connector.unit_number].outputs, drop_target.unit_number)
               else
                  if hash[drop_target.unit_number].link ~= nil then
                     hash[drop_target.unit_number].ent = drop_target
                     drop_target = hash[hash[drop_target.unit_number].link].ent
                  end
                  table.insert(hash[drop_target.unit_number].inputs, connector.unit_number)
                  table.insert(hash[connector.unit_number].outputs, drop_target.unit_number)
               end
            else
               if hash[drop_target.unit_number] == nil then
                  hash[drop_target.unit_number] = {
                     production_line = math.huge,
                     inputs = {},
                     outputs = {},
                     ent = drop_target
                  }
               end
               table.insert(hash[drop_target.unit_number].inputs, connector.unit_number)
               table.insert(hash[connector.unit_number].outputs, drop_target.unit_number)
            end
         end

         if pickup_target ~= nil then
            if pickup_target.type == "inserter" then
               explore_connector(pickup_target)
               local check = true
               for i, v in pairs(hash[pickup_target.unit_number].outputs) do
                  if v == connector.unit_number then
                     check = false
                  end
               end
               if check then
                  table.insert(hash[pickup_target.unit_number].outputs, connector.unit_number)
               end

               local check = true
               for i, v in pairs(hash[connector.unit_number].inputs) do
                  if v == pickup_target.unit_number then
                     check = false
                  end
               end
               if check then
                  table.insert(hash[connector.unit_number].inputs, pickup_target.unit_number)
               end

            elseif pickup_target.type == "transport-belt" then
               if hash[pickup_target.unit_number] == nil then
                  local belts = get_connected_belts(pickup_target)
                  for i, belt in pairs(belts.hash) do
                     hash[i] = {link = pickup_target.unit_number}
                  end
                  hash[pickup_target.unit_number] = {
                     production_line = math.huge,
                     inputs = {},
                     outputs = {connector.unit_number},
                     ent = pickup_target
                  }
                  table.insert(hash[connector.unit_number].outputs, pickup_target.unit_number)

               else
                  if hash[pickup_target.unit_number].link ~= nil then
                     hash[pickup_target.unit_number].ent = pickup_target
                     pickup_target = hash[hash[pickup_target.unit_number].link].ent
                  end
                  table.insert(hash[pickup_target.unit_number].outputs, connector.unit_number)
                  table.insert(hash[connector.unit_number].inputs, pickup_target.unit_number)
               end
            else
               if hash[pickup_target.unit_number] == nil then
                  hash[pickup_target.unit_number] = {
                     production_line = math.huge,
                     inputs = {},
                     outputs = {},
                     ent = pickup_target
                  }
               end
               table.insert(hash[pickup_target.unit_number].outputs, connector.unit_number)
               table.insert(hash[connector.unit_number].inputs, pickup_target.unit_number)

            end
         end

         local choices = {hash[connector.unit_number]}
         if drop_target ~= nil then
            table.insert(choices, hash[drop_target.unit_number])
         end
         if pickup_target ~= nil then
            table.insert(choices, hash[pickup_target.unit_number])
         end
         local line_choices = {}
         for i, choice in pairs(choices) do
            table.insert(line_choices, choice.production_line)
         end
         table.insert(line_choices, table.maxn(lines)+1)
         local new_line = math.min(unpack(line_choices))
         for i, choice in pairs(choices) do
            if choice.production_line ~= new_line then
               local old_line = choice.production_line
               if old_line ~= math.huge then
                  for i1, ent in pairs(lines[old_line]) do
                     hash[ent].production_line = new_line
                     lines[new_line] = lines[new_line] or {}
                     table.insert(lines[new_line], ent)
                  end
                  lines[old_line] = nil
               else
                  choice.production_line = new_line
                  if lines[new_line] == nil then
                     lines[new_line] = {}
                  end
                  table.insert(lines[new_line], choice.ent.unit_number)
               end
            end
         end
      end
   end

   for i, connector in pairs(connectors) do
      explore_connector(connector)
   end

--   print(table_size(lines))
--   print(table_size(hash))

--   local count = 0
--   for i, entry in pairs(hash) do
--      if entry.ent ~= nil then
--         count = count + 1
--   end
--   end
--   print(count)
   return {hash = hash, lines = lines}
end

function scan_for_warnings(L,H,pindex)
   local prod =       generate_production_network(pindex)
   local surf = game.get_player(pindex).surface
   local pos = players[pindex].cursor_pos
   local area = {{pos.x - L, pos.y - H}, {pos.x + L, pos.y + H}}
   local ents = surf.find_entities_filtered{area = area, type = entity_types}
   local warnings = {}
   warnings["noFuel"] = {}
   warnings["noRecipe"] = {}
   warnings["noInserters"] = {}
   warnings["noPower"] = {}
   warnings ["notConnected"] = {}
   for i, ent in pairs(ents) do
      if ent.prototype.burner_prototype ~= nil then
         if ent.energy == 0 then
            table.insert(warnings["noFuel"], ent)
         end
      end

      if ent.prototype.electric_energy_source_prototype ~= nil and ent.is_connected_to_electric_network() == false then
         table.insert(warnings["notConnected"], ent)
      elseif ent.prototype.electric_energy_source_prototype ~= nil and ent.energy == 0 then
         table.insert(warnings["noPower"], ent)
      end
      local recipe = nil
      if pcall(function()
         recipe = ent.get_recipe()
     end) then
         if recipe == nil and ent.type ~= "furnace" then
            table.insert(warnings["noRecipe"], ent)
         end
      end
      local check = false
      for i1, type in pairs(production_types) do
         if ent.type == type then
            check = true
         end
      end
      if check and prod.hash[ent.unit_number] == nil then
         table.insert(warnings["noInserters"], ent)
      end
   end
   local str = ""
   local result = {}
   for i, warning in pairs(warnings) do
      if #warning > 0 then
         str = str .. i .. " " .. #warning .. ", "
         table.insert(result, {name = i, ents = warning})
      end
   end
   if str == "" then
      str = "No warnings displayed    "
   end
   str = string.sub(str, 1, -3)
   return {summary = str, warnings = result}
end

function get_connected_lines(B)
   local left = {}
   local right = {}
   local frontier = {}
   local precursors = {}
   local hash = {}
   hash[B.unit_number] = true
   local upstreams = {}
   local inputs = B.belt_neighbours["inputs"]
   local outputs = B.belt_neighbours["outputs"]
   for i, belt in pairs(outputs) do
      if hash[belt.unit_number] ~= true then
         hash[belt.unit_number] = true
         table.insert(frontier, {side = 1, belt = belt})
      end
   end

      for i, belt in pairs(inputs) do
         if hash[belt.unit_number] ~= true then
            local side = 1
            if #inputs == 1 then
               side = 1
            elseif belt.direction == (B.direction + 2) % 8 then
               side = 0
               elseif belt.direction == (B.direction + 6) % 8 then
               side = 2
            end
               

            table.insert(precursors, {side = side, belt = belt})
         end
      end

   table.insert(left, B.get_transport_line(1))      
   table.insert(right, B.get_transport_line(2))

   while #frontier > 0 do
      local explored = table.remove(frontier, 1)
      local outputs = explored.belt.belt_neighbours["outputs"]
      local inputs = explored.belt.belt_neighbours["inputs"]
      for i, belt in pairs(outputs) do
         if hash[belt.unit_number] ~= true then
            hash[belt.unit_number] = true
            table.insert(frontier, {side = 1, belt = belt})
         end
      end

      for i, belt in pairs(inputs) do
         if hash[belt.unit_number] ~= true then
            local side = 1
            if explored.side == 0 or explored.side == 2 then
               side = explored.side
            elseif #inputs == 1 then
               side = 1
            elseif belt.direction == (explored.belt.direction + 2) % 8 then
               side = 0
               elseif belt.direction == (explored.belt.direction + 6) % 8 then
               side = 2
            end
               

            table.insert(upstreams, {side = side, belt = belt})
         end
      end
if explored.side == 0 then
         table.insert(left, explored.belt.get_transport_line(1))      
         table.insert(left, explored.belt.get_transport_line(2))
      elseif explored.side == 2 then
         table.insert(right, explored.belt.get_transport_line(1))      
         table.insert(right, explored.belt.get_transport_line(2))
               elseif explored.side == 1 then
         table.insert(left, explored.belt.get_transport_line(1))      
         table.insert(right, explored.belt.get_transport_line(2))
      end
   end

   for i, belt in pairs(upstreams) do
      if hash[belt.belt.unit_number] ~= true then
         hash[belt.belt.unit_number] = true
         table.insert(frontier, belt)
      end
   end

   while #frontier > 0 do
      local explored = table.remove(frontier, 1)
      local inputs = explored.belt.belt_neighbours["inputs"]

      for i, belt in pairs(inputs) do
         if hash[belt.unit_number] ~= true then
            hash[belt.unit_number] = true
            local side = 1
            if explored.side == 0 or explored.side == 2 then
               side = explored.side
            elseif #inputs == 1 then
               side = 1
            elseif belt.direction == (explored.belt.direction + 2) % 8 then
               side = 0
               elseif belt.direction == (explored.belt.direction + 6) % 8 then
               side = 2
            end
               

            table.insert(frontier, {side = side, belt = belt})
         end
      end
if explored.side == 0 then
         table.insert(left, explored.belt.get_transport_line(1))      
         table.insert(left, explored.belt.get_transport_line(2))
      elseif explored.side == 2 then
         table.insert(right, explored.belt.get_transport_line(1))      
         table.insert(right, explored.belt.get_transport_line(2))

               elseif explored.side == 1 then
         table.insert(left, explored.belt.get_transport_line(1))      
         table.insert(right, explored.belt.get_transport_line(2))

      end
   end

   for i, belt in pairs(precursors) do
      if hash[belt.belt.unit_number] ~= true then
         hash[belt.belt.unit_number] = true
         table.insert(frontier, belt)
      end
   end


   local downstream = {left = table.deepcopy(left), right = table.deepcopy(right)}
   local upstream = {left = {}, right = {}}

   while #frontier > 0 do
      local explored = table.remove(frontier, 1)
      local inputs = explored.belt.belt_neighbours["inputs"]

      for i, belt in pairs(inputs) do
         if hash[belt.unit_number] ~= true then
            hash[belt.unit_number] = true
            local side = 1
            if explored.side == 0 or explored.side == 2 then
               side = explored.side
            elseif #inputs == 1 then
               side = 1
            elseif belt.direction == (explored.belt.direction + 2) % 8 then
               side = 0
               elseif belt.direction == (explored.belt.direction + 6) % 8 then
               side = 2
            end
               

            table.insert(frontier, {side = side, belt = belt})
         end
      end
if explored.side == 0 then
         table.insert(left, explored.belt.get_transport_line(1))      
         table.insert(left, explored.belt.get_transport_line(2))
         table.insert(upstream.left, explored.belt.get_transport_line(1))      
         table.insert(upstream.left, explored.belt.get_transport_line(2))

      elseif explored.side == 2 then
         table.insert(right, explored.belt.get_transport_line(1))      
         table.insert(right, explored.belt.get_transport_line(2))
         table.insert(upstream.right, explored.belt.get_transport_line(1))      
         table.insert(upstream.right, explored.belt.get_transport_line(2))

               elseif explored.side == 1 then
         table.insert(left, explored.belt.get_transport_line(1))      
         table.insert(right, explored.belt.get_transport_line(2))
         table.insert(upstream.left, explored.belt.get_transport_line(1))      
         table.insert(upstream.right, explored.belt.get_transport_line(2))

      end
   end


   return {combined = {left = left, right = right}, upstream = upstream, downstream = downstream}

end
   
function get_connected_belts(B)
   local result = {}
   local frontier = {table.deepcopy(B)}
   local hash = {}
   hash[B.unit_number] = true
   while #frontier > 0 do
      local explored = table.remove(frontier, 1)
      local inputs = explored.belt_neighbours["inputs"]
      local outputs = explored.belt_neighbours["outputs"]
      for i, belt in pairs(inputs) do
         if hash[belt.unit_number] ~= true then
            hash[belt.unit_number] = true
            table.insert(frontier, table.deepcopy(belt))
         end
      end
      for i, belt in pairs(outputs) do
         if hash[belt.unit_number] ~= true then
            hash[belt.unit_number] = true
            table.insert(frontier, table.deepcopy(belt))
         end
      end
      table.insert(result, table.deepcopy(explored))
      
   end

   return {hash = hash, ents = result}
end

function prune_item_groups(array)
   if #groups == 0 then
      local dict = game.item_prototypes
      local a = get_iterable_array(dict)
      for i, v in ipairs(a) do
         local check1 = true
         local check2 = true

         for i1, v1 in ipairs(groups) do
            if v1.name == v.group.name then
               check1 = false
            end
            if v1.name == v.subgroup.name then
               check2 = false
            end
         end
         if check1 then
            table.insert(groups, v.group)
         end
         if check2 then
            table.insert(groups, v.subgroup)
         end
      end         
   end
   local i = 1
   while i < #array and array ~= nil and array[i] ~= nil do
      local check = true
      for i1, v in ipairs(groups) do
         if v ~= nil and array[i].name == v.name then
            i = i + 1
            check = false
            break
         end
      end
      if check then
         table.remove(array, i)
      end
   end
end
         

function read_item_selector_slot(pindex, start_phrase)
   start_phrase = start_phrase or ""
   printout(start_phrase .. players[pindex].item_cache[players[pindex].item_selector.index].name, pindex)
end

function get_iterable_array(dict)
   result = {}
   for i, v in pairs(dict) do
      table.insert(result, v)
   end
   return result
end

function get_substring_before_space(str)
   local first, final = string.find(str," ")
   if first == nil or first == 1 then
      return str
   else
      return string.sub(str,1,first-1)
   end
end

function get_substring_before_comma(str)
   local first, final = string.find(str,",")
   if first == nil or first == 1 then
      return str
   else
      return string.sub(str,1,first-1)
   end
end

function get_substring_before_dash(str)
   local first, final = string.find(str,"-")
   if first == nil or first == 1 then
      return str
   else
      return string.sub(str,1,first-1)
   end
end

function get_ent_area_from_name(ent_name,pindex)
   local ents = game.get_player(pindex).surface.find_entities_filtered{name = ent_name, limit = 1}
   if #ents == 0 then
      return -1
   else
      return ents[1].tile_height * ents[1].tile_width
   end
end

function confirm_ent_is_in_area(ent_name, area_left_top, area_right_bottom, pindex)
   local ents = game.get_player(pindex).surface.find_entities_filtered{name = ent_name, area = {area_left_top,area_right_bottom}, limit = 1}
   return #ents > 0
end

function get_scan_summary(scan_left_top, scan_right_bottom, pindex)      
   local result = ""
   local explored_left_top = {x = math.floor((players[pindex].cursor_pos.x - 1 - players[pindex].cursor_size) / 32), y = math.floor((players[pindex].cursor_pos.y - 1 - players[pindex].cursor_size)/32)}
   local explored_right_bottom = {x = math.floor((players[pindex].cursor_pos.x + 1 + players[pindex].cursor_size)/32), y = math.floor((players[pindex].cursor_pos.y + 1 + players[pindex].cursor_size)/32)}
   local count = 0
   local total = 0
   for i = explored_left_top.x, explored_right_bottom.x do
      for i1 = explored_left_top.y, explored_right_bottom.y do
         if game.get_player(pindex).surface.is_chunk_generated({i, i1}) then
            count = count + 1
         end
         total = total + 1
      end
   end
   if total > 0 and count < 1 then
      result = result .. "Charted 0%, you need to chart this area by approaching it or using a radar."
      return result
   elseif total > 0 and count < total then
      result = result .. "Charted " .. math.floor((count/total) * 100) .. "%, "
   end
   
   local percentages = {}
   local percent_total = 0
   local surf = game.get_player(pindex).surface
   --Scan for Tiles and Resources, because they behave weirdly in scan_area due to aggregation, or are skipped
   local percent = 0
   local res_count = surf.count_tiles_filtered{ name = {"water", "deepwater", "water-green", "deepwater-green", "water-shallow", "water-mud", "water-wube"}, area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "water", percent = percent, count = "resource"})
   end
   percent_total = percent_total + percent--water counts as filling a space
   
   res_count = surf.count_tiles_filtered{ name = "stone-path", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "stone-brick-path", percent = percent, count = "flooring"})
   end
   
   res_count = surf.count_tiles_filtered{ name = {"concrete","hazard-concrete-left","hazard-concrete-right"}, area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "concrete", percent = percent, count = "flooring"})
   end
   
   res_count = surf.count_tiles_filtered{ name = {"refined-concrete","refined-hazard-concrete-left","refined-hazard-concrete-right"}, area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "refined-concrete", percent = percent, count = "flooring"})
   end
   
   res_count = surf.count_entities_filtered{ name = "coal", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "coal", percent = percent, count = "resource"})
   end
   
   res_count = surf.count_entities_filtered{ name = "stone", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "stone", percent = percent, count = "resource"})
   end
   
   res_count = surf.count_entities_filtered{ name = "iron-ore", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "iron-ore", percent = percent, count = "resource"})
   end
   
   res_count = surf.count_entities_filtered{ name = "copper-ore", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "copper-ore", percent = percent, count = "resource"})
   end
   
   res_count = surf.count_entities_filtered{ name = "uranium-ore", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "uranium-ore", percent = percent, count = "resource"})
   end
   
   res_count = surf.count_entities_filtered{ name = "crude-oil", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((9 * res_count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)
   if percent > 0 then
      table.insert(percentages, {name = "crude-oil", percent = percent, count = "resource"})
   end
   
   res_count = surf.count_entities_filtered{ type = "tree", area = {scan_left_top,scan_right_bottom} }
   percent = math.floor((res_count * 8 / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .5)--trees are bigger than 1 tile
   if percent > 0 then
      table.insert(percentages, {name = "trees", percent = percent, count = res_count})
   end
   percent_total = percent_total + percent
   
   if #players[pindex].nearby.ents > 0 then --Note: Resources are included here as aggregates.
      for i, ent in ipairs(players[pindex].nearby.ents) do
         local area = 0
         --this confirmation is necessary because all we have is the ent name, and some distant resources show up on the list.
         if confirm_ent_is_in_area( get_substring_before_space(get_substring_before_comma(ent.name)) , scan_left_top , scan_right_bottom, pindex) then
            area = get_ent_area_from_name(get_substring_before_space(get_substring_before_comma(ent.name)),pindex)
            if area == -1 then
               area = 1
               game.get_player(pindex).print(get_substring_before_space(get_substring_before_comma(ent.name)) .. " could not be found for the area check ",{volume_modifier = 0})--bug: unable to get area from name
            end
         end 
         local percentage = math.floor((area * players[pindex].nearby.ents[i].count / ((1+players[pindex].cursor_size * 2) ^2) * 100) + .95)--Tolerate up to 0.05%
         if not ent.aggregate and percentage > 0 then
            table.insert(percentages, {name = ent.name, percent = percentage, count = players[pindex].nearby.ents[i].count})
         end
         percent_total = percent_total + percentage
      end
      table.sort(percentages, function(k1, k2)
         return k1.percent > k2.percent
      end)
      result = result .. " Area contains "
      local i = 1
      while i <= # percentages and (i <= 5 or percentages[i].percent > 1) do
         result = result .. percentages[i].count .. " " .. percentages[i].name .. " " .. percentages[i].percent .. "%, "
         i = i + 1
      end
      if percent_total == 0 then--Note there are still some entities in here, but with zero area...
         result = result .. " nothing "
      end
      result = result .. ", total space occupied " .. math.floor(percent_total) .. " percent " 
   else
      result = result .. " Empty Area  "
   end
   
   return result
end

function draw_area_as_cursor(scan_left_top,scan_right_bottom,pindex)
   local h_tile = players[pindex].cursor_tile_highlight_box
   if h_tile ~= nil then
      rendering.destroy(h_tile)
   end
   h_tile = rendering.draw_rectangle{color = {0.75,1,1},surface = game.get_player(pindex).surface, left_top = scan_left_top, right_bottom = scan_right_bottom, draw_on_ground = true, players = nil}
   rendering.set_visible(h_tile,true)
   players[pindex].cursor_tile_highlight_box = h_tile 
   
   --Recolor cursor boxes if multiplayer
   if game.is_multiplayer() then
      set_cursor_colors_to_player_colors(pindex)
   end
end
   
--Sort scan results by distance or count
function scan_sort(pindex)
   for i, name in ipairs(players[pindex].nearby.ents   ) do
      local i1 = 1
      while i1 <= #name.ents do --this appears to be removing invalid ents within a set.
         if not name.ents[i1].valid and not name.aggregate then
            table.remove(name.ents, i1)
         else
            i1 = i1 + 1
         end
      end
      if #name.ents == 0 then --this appears to be removing a set that has become empty.
         table.remove(players[pindex].nearby.ents, i)
      end
   end

   if players[pindex].nearby.count == false then
      --Sort by distance to player position
      table.sort(players[pindex].nearby.ents, function(k1, k2) 
         local pos = players[pindex].position
         local surf = game.get_player(pindex).surface
         local ent1 = nil
         local ent2 = nil
         if k1.name == "water" then
            table.sort( k1.ents , function(k3, k4) 
               return squared_distance(pos, k3.position) < squared_distance(pos, k4.position)
            end)
            ent1 = k1.ents[1]
         else
            if k1.aggregate then
               table.sort( k1.ents , function(k3, k4) 
                  return squared_distance(pos, k3.position) < squared_distance(pos, k4.position)
               end)
               ent1 = k1.ents[1]
            else
               ent1 = surf.get_closest(pos, k1.ents)
            end
         end
         if k2.name == "water" then
            table.sort( k2.ents , function(k3, k4) 
               return squared_distance(pos, k3.position) < squared_distance(pos, k4.position)
            end)
            ent2 = k2.ents[1]
         else
            if k2.aggregate then
               table.sort( k2.ents , function(k3, k4) 
                  return squared_distance(pos, k3.position) < squared_distance(pos, k4.position)
               end)
               ent2 = k2.ents[1]
            else
               ent2 = surf.get_closest(pos, k2.ents)
            end
         end
         return squared_distance(pos, ent1.position) < squared_distance(pos, ent2.position)
      end)
            
   else
      --Sort table by count
      table.sort(players[pindex].nearby.ents, function(k1, k2)
         return k1.count > k2.count
      end)
   end
   populate_categories(pindex)

end
   


function center_of_tile(pos)
   return {x = math.floor(pos.x)+0.5, y = math.floor(pos.y)+ .5}
end

function get_power_string(power)
   result = ""
   if power > 1000000000000 then
      power = power/1000000000000
      result = result .. string.format(" %.1f Terawatts", power) 
   elseif power > 1000000000 then
      power = power / 1000000000
      result = result .. string.format(" %.1f Gigawatts", power) 
   elseif power > 1000000 then
      power = power / 1000000
      result = result .. string.format(" %.1f Megawatts", power) 
   elseif power > 1000 then
      power = power / 1000
      result = result .. string.format(" %.1f Kilowatts", power) 
   else
      result = result .. string.format(" %.1f Watts", power) 
   end
   return result
end

function get_adjacent_source(box, pos, dir)
   local result = {position = pos, direction = ""}
   ebox = table.deepcopy(box)
   if dir == 1 or dir == 3 then
      ebox.left_top.x = box.left_top.y
      ebox.left_top.y = box.left_top.x
      ebox.right_bottom.x = box.right_bottom.y
      ebox.right_bottom.y = box.right_bottom.x
   end
--   print(ebox.left_top.x .. " " .. ebox.left_top.y)
   ebox.left_top.x = math.ceil(ebox.left_top.x * 2)/2
   ebox.left_top.y = math.ceil(ebox.left_top.y * 2)/2
   ebox.right_bottom.x = math.floor(ebox.right_bottom.x * 2)/2
   ebox.right_bottom.y = math.floor(ebox.right_bottom.y * 2)/2

   if pos.x < ebox.left_top.x then
      result.position.x = result.position.x + 1
      result.direction = "West"
         elseif pos.x > ebox.right_bottom.x then
      result.position.x = result.position.x - 1
      result.direction = "East"
   elseif pos.y < ebox.left_top.y then
      result.position.y = result.position.y + 1
      result.direction = "North"
   elseif pos.y > ebox.right_bottom.y then
      result.position.y = result.position.y - 1
      result.direction = "South"
   end
   return result
end

function read_technology_slot(pindex, start_phrase)
   start_phrase = start_phrase or ""
   local techs = {}
   if players[pindex].technology.category == 1 then
      techs = players[pindex].technology.lua_researchable
   elseif players[pindex].technology.category == 2 then
      techs = players[pindex].technology.lua_locked
   elseif players[pindex].technology.category == 3 then
      techs = players[pindex].technology.lua_unlocked
   end
   
   if next(techs) ~= nil and players[pindex].technology.index > 0 and players[pindex].technology.index <= #techs then
      local tech = techs[players[pindex].technology.index]
      if tech.valid then
         printout(start_phrase .. localising.get(tech,pindex), pindex)
      else
         printout("Error loading technology", pindex)
      end
   else
      printout("No technologies in this category yet", pindex)
   end
end

function populate_categories(pindex)
   players[pindex].nearby.resources = {}
   players[pindex].nearby.containers = {}
   players[pindex].nearby.buildings = {}
   players[pindex].nearby.vehicles = {}
   players[pindex].nearby.players = {}
   players[pindex].nearby.enemies = {}
   players[pindex].nearby.other = {}

   for i, ent in ipairs(players[pindex].nearby.ents) do
      if ent.aggregate then
         table.insert(players[pindex].nearby.resources, ent)               
      else
         while #ent.ents > 0 and ent.ents[1].valid == false do
            table.remove(ent.ents, 1)
         end
         if #ent.ents == 0 then
            print("Empty ent")
         elseif ent.name == "water" then
            table.insert(players[pindex].nearby.resources, ent)      
         elseif ent.ents[1].type == "resource" or ent.ents[1].type == "tree" or ent.ents[1].name == "sand-rock-big" or ent.ents[1].name == "rock-big" or ent.ents[1].name == "rock-huge" then --Note: There is no rock type, so they are specified by name.
            table.insert(players[pindex].nearby.resources, ent)
         elseif ent.ents[1].type == "container" or ent.ents[1].type == "logistic-container" then
            table.insert(players[pindex].nearby.containers, ent)
         elseif ent.ents[1].prototype.is_building and ent.ents[1].type ~= "unit-spawner" and ent.ents[1].type ~= "turret" and ent.ents[1].name ~= "train-stop" then
            table.insert(players[pindex].nearby.buildings, ent)
         elseif ent.ents[1].type == "car" or ent.ents[1].type == "locomotive" or ent.ents[1].type == "cargo-wagon" or ent.ents[1].type == "fluid-wagon" or ent.ents[1].type == "artillery-wagon" or ent.ents[1].type == "spider-vehicle" or ent.ents[1].name == "train-stop" then 
            table.insert(players[pindex].nearby.vehicles, ent)
         elseif ent.ents[1].type == "character" or ent.ents[1].type == "character-corpse" then
            table.insert(players[pindex].nearby.players, ent)
         elseif ent.ents[1].type == "unit" or ent.ents[1].type == "unit-spawner" or ent.ents[1].type == "turret" then
            table.insert(players[pindex].nearby.enemies, ent)
         elseif ent.ents[1].type == "simple-entity" or ent.ents[1].type == "simple-entity-with-owner" or ent.ents[1].type == "entity-ghost" or ent.ents[1].type == "item-entity" then
            table.insert(players[pindex].nearby.other, ent)
         end
      end
   end
   --for debugging
   -- game.print("resource count: "  .. #players[pindex].nearby.resources,{volume_modifier = 0})
   -- game.print("container count: " .. #players[pindex].nearby.containers,{volume_modifier = 0})
   -- game.print("buildings count: " .. #players[pindex].nearby.buildings,{volume_modifier = 0})
   -- game.print("vehicles count: "  .. #players[pindex].nearby.vehicles,{volume_modifier = 0})
   -- game.print("'players' count: " .. #players[pindex].nearby.players,{volume_modifier = 0})
   -- game.print("enemies count: "   .. #players[pindex].nearby.enemies,{volume_modifier = 0})
   -- game.print("other count: "     .. #players[pindex].nearby.other,{volume_modifier = 0})
   
end

function read_belt_slot(pindex, start_phrase)
   start_phrase = start_phrase or ""
   local stack = nil
   local array = {}
   local result = start_phrase
   local direction = players[pindex].belt.direction
   
   --Read lane direction
   if players[pindex].belt.side == 1 then
      if direction == 0 then 
         result = result .. "West lane "
      elseif direction == 4 then
         result = result .. "East lane "
      elseif direction == 6 then
         result = result .. "South lane "
      elseif direction == 2 then
         result = result .. "North lane " 
      else
         result = result .. "Unspecified lane, "
      end
   elseif players[pindex].belt.side == 2 then
      if direction == 0 then 
         result = result .. "East lane "
      elseif direction == 4 then
         result = result .. "West lane "
      elseif direction == 6 then
         result = result .. "North lane "
      elseif direction == 2 then
         result = result .. "South lane " 
      else
         result = result .. "Unspecified lane, "
      end

   end
   --Read lane contents
   if players[pindex].belt.sector == 1 and players[pindex].belt.side == 1 then
      array = players[pindex].belt.line1
   elseif players[pindex].belt.sector == 1 and players[pindex].belt.side == 2 then
      array = players[pindex].belt.line2
   elseif players[pindex].belt.sector == 2 then
      if players[pindex].belt.side == 1 then
         array = players[pindex].belt.network.combined.left
      elseif players[pindex].belt.side == 2 then
         array = players[pindex].belt.network.combined.right
      end
   elseif players[pindex].belt.sector == 3 then
      if players[pindex].belt.side == 1 then
         array = players[pindex].belt.network.downstream.left
      elseif players[pindex].belt.side == 2 then
         array = players[pindex].belt.network.downstream.right
      end
   elseif players[pindex].belt.sector == 4 then
      if players[pindex].belt.side == 1 then
         array = players[pindex].belt.network.upstream.left
      elseif players[pindex].belt.side == 2 then
         array = players[pindex].belt.network.upstream.right
      end

   else
      return
   end
   pcall(function()
      stack = array[players[pindex].belt.index]
   end)

   if stack ~= nil and stack.valid_for_read and stack.valid then
      result = result .. localising.get(stack,pindex) .. " x " .. stack.count
      if players[pindex].belt.sector > 1 then
         result = result .. ", " .. stack.percent .. "%"
      end
   else
      result = result .. "Empty slot"
   end
   printout(result, pindex)
end


function reset_rotation(pindex)
   players[pindex].building_direction = -1
end

function read_building_recipe(pindex, start_phrase)
   start_phrase = start_phrase or ""
   if players[pindex].building.recipe_selection then --inside the selector
      local recipe = players[pindex].building.recipe_list[players[pindex].building.category][players[pindex].building.index]
      if recipe and recipe.valid then
         printout(start_phrase .. localising.get(recipe,pindex) .. " " .. recipe.category .. " " .. recipe.group.name .. " " .. recipe.subgroup.name, pindex)
      else
         printout(start_phrase .. "blank",pindex)
      end
   else
      local recipe = players[pindex].building.recipe
      if recipe ~= nil then
         printout(start_phrase .. "Currently Producing: " .. recipe.name, pindex)
      else
         printout(start_phrase .. "Press left bracket", pindex)
      end
   end
end
      

function read_building_slot(pindex, prefix_inventory_size_and_name)
   local building_sector=players[pindex].building.sectors[players[pindex].building.sector]
   if building_sector.name == "Filters" then 
      local inventory = building_sector.inventory
      local start_phrase = #inventory .. " " .. building_sector.name .. ", "
      if not prefix_inventory_size_and_name then
         start_phrase = ""
      end
      printout(start_phrase .. players[pindex].building.index .. ", " .. building_sector.inventory[players[pindex].building.index], pindex)
   elseif building_sector.name == "Fluid" then 
      local box = building_sector.inventory
      local capacity = box.get_capacity(players[pindex].building.index)
      local type = box.get_prototype(players[pindex].building.index).production_type
      local fluid = box[players[pindex].building.index]
      local len = #box
      local start_phrase = len .. " " .. building_sector.name .. ", "
      if not prefix_inventory_size_and_name then
         start_phrase = ""
      end
      --fluid = {name = "water", amount = 1}
      local name  = "Any"
      local amount = 0
      if fluid ~= nil then
         amount = fluid.amount
         name = fluid.name--does not locallise..?**
      end --laterdo use fluidbox.get_locked_fluid(i) if needed.
      --Read the fluid ingredients & products
      --Note: We could have separated by input/output but right now the "type" is "input" for all fluids it seeems?
      local recipe = players[pindex].building.recipe
      if recipe ~= nil then
         local index = players[pindex].building.index
         local input_fluid_count = 0
         local input_item_count = 0
         for i, v in pairs(recipe.ingredients) do
            if v.type == "fluid" then
               input_fluid_count = input_fluid_count + 1
            else
               input_item_count = input_item_count + 1
            end
         end
         local output_fluid_count = 0
         local output_item_count = 0
         for i, v in pairs(recipe.products) do
            if v.type == "fluid" then
               output_fluid_count = output_fluid_count + 1
            else
               output_item_count = output_item_count + 1
            end
         end
         if index < 0 then
            index = 0
         end
         local prev_name = name
         name = "Empty slot reserved for "
         if index <= input_fluid_count then
            index = index + input_item_count
            for i, v in pairs(recipe.ingredients) do
               if v.type == "fluid" and i == index then
                  name = name .. " input " .. v.name
                  if prev_name ~= "Any" then
                     name = "input " .. prev_name .. " x " .. math.floor(0.5 + amount)
                  end
               end
            end
         else
            index = index - input_fluid_count
            index = index + output_item_count
            for i, v in pairs(recipe.products) do
               if v.type == "fluid" and i == index then
                  name = name .. " output " .. v.name
                  if prev_name ~= "Any" then
                     name = "output " .. prev_name .. " x " .. math.floor(0.5 + amount)
                  end
               end
            end
         end
      else
         name = name .. " x " .. math.floor(0.5 + amount)
      end
      --Read the fluid found, including amount if any
      printout(start_phrase .. " " .. name, pindex)
   
   elseif #building_sector.inventory > 0 then
      local inventory=building_sector.inventory
      local start_phrase = #inventory .. " " .. building_sector.name .. ", "
      if inventory.supports_bar() and #inventory > inventory.get_bar() - 1 then
         --local unlocked = inventory.supports_bar() and inventory.get_bar() - 1 or nil
         local unlocked = inventory.get_bar() - 1
         start_phrase = start_phrase .. ", " .. unlocked .. " unlocked, "
      end
      if not prefix_inventory_size_and_name then
         start_phrase = ""
      end
      --Mention if a slot is locked
      if inventory.supports_bar() and players[pindex].building.index > inventory.get_bar() - 1 then
         start_phrase = start_phrase .. " locked "
      end
      --Read the slot stack
      stack = building_sector.inventory[players[pindex].building.index]
      if stack and stack.valid_for_read and stack.valid then
         printout(start_phrase .. localising.get(stack,pindex) .. " x " .. stack.count, pindex)
      else
         --Read the "empty slot"
         local result = "Empty slot" 
         if building_sector.name == "Modules" then
            result = "Empty module slot" 
         end
         local recipe = players[pindex].building.recipe
         if recipe ~= nil then 
            if building_sector.name == "Input" then 
               --For input slots read the recipe ingredients
               result = result .. " reserved for "
               for i, v in pairs(recipe.ingredients) do
                  if v.type == "item" and i == players[pindex].building.index then
                     result = result .. v.name --.. " or "
                  end
               end
               --result = result .. "nothing"
            elseif building_sector.name == "Output" then 
               --For output slots read the recipe products
               result = result .. " reserved for "
               for i, v in pairs(recipe.products) do
                  if v.type == "item" and i == players[pindex].building.index then
                     result = result .. v.name --does not localise?**
                  end
               end
               --result = result .. "nothing"
            end
         elseif players[pindex].building.ent ~= nil and players[pindex].building.ent.valid and players[pindex].building.ent.type == "lab" then
            --laterdo switch to {"item-name.".. ent.prototype.lab_inputs[players[pindex].building.index] }
            result = result .. " reserved for science pack type " .. players[pindex].building.index
         elseif players[pindex].building.ent ~= nil and players[pindex].building.ent.valid and players[pindex].building.ent.type == "roboport" then
            result = result .. " reserved for worker robots " 
         end
         printout(start_phrase .. result, pindex)
      end
   elseif prefix_inventory_size_and_name then
         printout("0 " .. building_sector.name,pindex)
   end
end

function factorio_default_sort(k1, k2) 
   if k1.group.order ~= k2.group.order then
      return k1.group.order < k2.group.order
   elseif k1.subgroup.order ~= k2.subgroup.order then
      return k1.subgroup.order < k2.subgroup.order
   elseif k1.order ~= k2.order then
      return k1.order < k2.order
   else               
      return k1.name < k2.name
   end
end


function get_recipes(pindex, building)
   if not building then
      return {}
   end
   local category_filters={}
   for category_name, _ in pairs(building.prototype.crafting_categories) do
      table.insert(category_filters, {filter="category", category=category_name})
   end
   local all_machine_recipes = game.get_filtered_recipe_prototypes(category_filters)
   local unlocked_machine_recipes = {}
   local force_recipes = game.get_player(pindex).force.recipes
   for recipe_name, recipe in pairs(all_machine_recipes) do
      if force_recipes[recipe_name] ~= nil and force_recipes[recipe_name].enabled then
         if unlocked_machine_recipes[recipe.group.name] == nil then
            unlocked_machine_recipes[recipe.group.name]={}
         end
         table.insert(unlocked_machine_recipes[recipe.group.name],force_recipes[recipe.name])
      end
   end
   local result={}
   for group, recipes in pairs(unlocked_machine_recipes) do
      table.insert(result,recipes)
   end
   return result
end

function get_tile_dimensions(item, dir)
   if item.place_result ~= nil then
      local dimensions = item.place_result.selection_box
      x = math.ceil(dimensions.right_bottom.x - dimensions.left_top.x)
      y = math.ceil(dimensions.right_bottom.y - dimensions.left_top.y)
      if (dir/2)%2 == 0 then
         return {x = x, y = y}
      else
         return {x = y, y = x}
      end
   end
   return {x = 0, y = 0}
end

function read_crafting_queue(pindex, start_phrase)
   start_phrase = start_phrase or ""
   if players[pindex].crafting_queue.max ~= 0 then
      item = players[pindex].crafting_queue.lua_queue[players[pindex].crafting_queue.index]
      printout(start_phrase .. item.recipe .. " x " .. item.count, pindex)
   else
      printout(start_phrase .. "Blank", pindex)
   end
end
   
function load_crafting_queue(pindex)
   if players[pindex].crafting_queue.lua_queue ~= nil then
      players[pindex].crafting_queue.lua_queue = game.get_player(pindex).crafting_queue
      if players[pindex].crafting_queue.lua_queue ~= nil then
         delta = players[pindex].crafting_queue.max - #players[pindex].crafting_queue.lua_queue
         players[pindex].crafting_queue.index = math.max(1, players[pindex].crafting_queue.index - delta)
         players[pindex].crafting_queue.max = #players[pindex].crafting_queue.lua_queue
      else
      players[pindex].crafting_queue.index = 1
      players[pindex].crafting_queue.max = 0
      end
   else
      players[pindex].crafting_queue.lua_queue = game.get_player(pindex).crafting_queue
   players[pindex].crafting_queue.index = 1
      if players[pindex].crafting_queue.lua_queue ~= nil then
      players[pindex].crafting_queue.max = # players[pindex].crafting_queue.lua_queue
      else
         players[pindex].crafting_queue.max = 0
      end
   end
end

function read_crafting_slot(pindex, start_phrase)
   start_phrase = start_phrase or ""
   recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index]
   if recipe.valid == true then
      if recipe.category == "smelting" then
         printout(start_phrase .. localising.get(recipe,pindex) .. " can only be crafted by a furnace.", pindex)
      else
         printout(start_phrase .. localising.get(recipe,pindex) .. " " .. recipe.category .. " " .. recipe.group.name .. " " .. game.get_player(pindex).get_craftable_count(recipe.name), pindex)
      end
      else
      printout("Blank",pindex)
   end
end

--Reads a player inventory slot
function read_inventory_slot(pindex, start_phrase_in)
   local start_phrase = start_phrase_in or ""
   local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
   if stack and stack.valid_for_read and stack.valid == true then
      printout(start_phrase .. localising.get(stack,pindex) .. " x " .. stack.count .. " " .. stack.prototype.subgroup.name , pindex)
   else
      printout(start_phrase .. "Empty Slot",pindex)
   end
end


function set_quick_bar(index, pindex)
   local page = game.get_player(pindex).get_active_quick_bar_page(1)-1
   local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
   if stack and stack.valid_for_read and stack.valid == true then
      game.get_player(pindex).set_quick_bar_slot(index + 10*page, stack) 
      printout("Assigned " .. index, pindex)

   else
      game.get_player(pindex).set_quick_bar_slot(index + 10*page, nil) 
      printout("Unassigned " .. index, pindex)
   end
end

function read_hand(pindex)
   if players[pindex].skip_read_hand == true then
      players[pindex].skip_read_hand = false
      return
   end
   local cursor_stack=game.get_player(pindex).cursor_stack
   if cursor_stack and cursor_stack.valid and cursor_stack.valid_for_read then
      local out={"access.cursor-description"}
      table.insert(out,cursor_stack.prototype.localised_name)
      local build_entity = cursor_stack.prototype.place_result
      if build_entity and build_entity.supports_direction then
         table.insert(out,1)
         table.insert(out,{"access.facing-direction",players[pindex].building_direction * dirs.east})
      else
         table.insert(out,0)
         table.insert(out,"")
      end
      table.insert(out,cursor_stack.count)
      local extra = game.get_player(pindex).get_main_inventory().get_item_count(cursor_stack.name)
      if extra > 0 then
         table.insert(out,cursor_stack.count+extra)
      else
         table.insert(out,0)
      end
      printout(out, pindex)
   else
      printout({"access.empty_cursor"}, pindex)
   end
end

--Stores the hand item in the player inventory and reads it from the first found player inventory slot, CONTROL + Q
--NOTE: laterdo can use player.hand_location in the future if it has advantages
function locate_hand_in_player_inventory(pindex)
   local p = game.get_player(pindex)
   local inv = p.get_main_inventory() 
   local stack = p.cursor_stack
   
   --Check if stack empty and menu supported
   if stack == nil or not stack.valid_for_read or not stack.valid then
      --Hand is empty
      return
   end
   if players[pindex].in_menu and players[pindex].menu ~= "inventory" then
      --Unsupported menu type, laterdo add support for building menu and closing the menu with a call
      printout("Another menu is open.",pindex)
      return
   end
   if not players[pindex].in_menu then
      --Open the inventory if nothing is open
      players[pindex].in_menu = true
      players[pindex].menu = "inventory"
      p.opened = p
   end
   --Save the hand stack item name
   local item_name = stack.name
   --Empty hand stack (clear cursor stack)
   players[pindex].skip_read_hand = true
   local successful = p.clear_cursor()
   if not successful then
      local message = "Unable to empty hand"
      if inv.count_empty_stacks() == 0 then
         message = message .. ", inventory full"
      end
      printout(message,pindex)
      return
   end
    
   --Iterate the inventory until you find the matching item name's index
   local found = false
   local i = 0
   while not found and i < #inv do
      i = i + 1
      if inv[i] and inv[i].valid_for_read and inv[i].name == item_name then
         found = true
      end
   end
   --If found, read it from the inventory
   if not found then
      printout("Error: " .. localising.get(stack,pindex) .. " not found in player inventory",pindex)
      return
   else
      players[pindex].inventory.index = i
      read_inventory_slot(pindex, "inventory ")
   end
   
end

--Stores the hand item in the player inventory and reads it from the first found building output slot, CONTROL + Q
function locate_hand_in_building_output_inventory(pindex)
   local p = game.get_player(pindex)
   local inv = nil
   local stack = p.cursor_stack
   local pb = players[pindex].building 
   
   --Check if stack empty and menu supported
   if stack == nil or not stack.valid_for_read or not stack.valid then
      --Hand is empty
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "building" and pb.sectors and pb.sectors[pb.sector] and pb.sectors[pb.sector].name == "Output" then
      inv = p.opened.get_output_inventory()
   else
      --Unsupported menu type
      return
   end

   --Save the hand stack item name
   local item_name = stack.name
   --Empty hand stack (clear cursor stack)
   players[pindex].skip_read_hand = true
   local successful = p.clear_cursor()
   if not successful then
      local message = "Unable to empty hand"
      if inv.count_empty_stacks() == 0 then
         message = message .. ", inventory full"
      end
      printout(message,pindex)
      return
   end

   --Iterate the inventory until you find the matching item name's index
   local found = false
   local i = 0
   while not found and i < #inv do
      i = i + 1
      if inv[i] and inv[i].valid_for_read and inv[i].name == item_name then
         found = true
      end
   end
   --If found, read it from the inventory
   if not found then
      printout(localising.get(stack,pindex) .. " not found in building output",pindex)
      return
   else
      players[pindex].building.index = i
      read_building_slot(pindex, false)
   end
   
end

--Locate the item in hand from the crafting menu. Closes some other menus, does not run in some other menus, uses the new search fn.
function locate_hand_in_crafting_menu(pindex)
   local p = game.get_player(pindex)
   local inv = p.get_main_inventory() 
   local stack = p.cursor_stack
   
   --Check if stack empty and menu supported
   if stack == nil or not stack.valid_for_read or not stack.valid then
      --Hand is empty
      return
   end
   if players[pindex].in_menu and players[pindex].menu ~= "inventory" and players[pindex].menu ~= "building" and players[pindex].menu ~= "crafting" then
      --Unsupported menu types...
      printout("Another menu is open.",pindex)
      return
   end
   
   --Open the crafting Menu
   close_menu_resets(pindex)
   players[pindex].in_menu = true
   players[pindex].menu = "crafting"
   p.opened = p
   
   --Get the name
   local item_name = string.lower(get_substring_before_dash(localising.get(stack.prototype,pindex)))
   players[pindex].menu_search_term = item_name
   
   --Empty hand stack (clear cursor stack) after getting the name 
   players[pindex].skip_read_hand = true
   local successful = p.clear_cursor()
   if not successful then
      local message = "Unable to empty hand"
      if inv.count_empty_stacks() == 0 then
         message = message .. ", inventory full"
      end
      printout(message,pindex)
      return
   end

   --Run the search
   menu_search_get_next(pindex,item_name,nil)
end

function read_quick_bar(index,pindex)
   page = game.get_player(pindex).get_active_quick_bar_page(1)-1
   local item = game.get_player(pindex).get_quick_bar_slot(index+ 10*page)
   if item ~= nil then
      local count = game.get_player(pindex).character.get_main_inventory().get_item_count(item.name)
      local stack = game.get_player(pindex).cursor_stack
      if stack and stack.valid_for_read then
         count = count + stack.count
         printout("unselected " .. item.name .. " x " .. count, pindex)
      else
         printout("selected " .. item.name .. " x " .. count, pindex)
      end

   else
      printout("Empty Slot",pindex)
   end

end

function target(pindex)
   local ent = get_selected_ent(pindex)
   if ent and not players[pindex].vanilla_mode then
         move_cursor_map(ent.position,pindex)
   elseif not players[pindex].vanilla_mode then
         move_cursor_map(players[pindex].cursor_pos, pindex)
   end
end

function move_cursor_map(position,pindex)
   local player = players[pindex]
   local pixels = mult_position( sub_position(position, player.position), 32*player.zoom)
   local screen = game.players[pindex].display_resolution
   screen = {x = screen.width, y = screen.height}
   pixels = add_position(pixels,mult_position(screen,0.5))
   move_cursor(pixels.x, pixels.y, pindex)
end

function move_cursor(x,y, pindex)
   if x >= 0 and y >=0 and x < game.players[pindex].display_resolution.width and y < game.players[pindex].display_resolution.height then
      print ("setCursor " .. pindex .. " " .. math.ceil(x) .. "," .. math.ceil(y))
   end
end

function tile_cycle(pindex)
   local tile=players[pindex].tile
   tile.index = tile.index + 1
   if tile.index > #tile.ents then
      tile.index = 0
   end
   local ent = get_selected_ent(pindex)
   if ent then
      printout(ent_info(pindex,ent,""),pindex)
   else
      printout(tile.tile, pindex)
   end
end
      
function check_for_player(index)
   if not players then
      global.players = global.players or {}
      players = global.players
   end
   if players[index] == nil then
   initialize(game.get_player(index))
   return false
   else
      return true
   end
end

function printout(str, pindex)
   if pindex ~= nil and pindex > 0 then
      players[pindex].last = str
   else
      return
   end
   if players[pindex].vanilla_mode == nil then
      players[pindex].vanilla_mode = false
   end
   if not players[pindex].vanilla_mode then
      localised_print{"","out "..pindex.." ",str}
   end
end

function repeat_last_spoken(pindex)
   printout(players[pindex].last, pindex)
end

--Creates the scanner results list
function scan_index(pindex)
   if not check_for_player(pindex) then
      printout("Scan pindex error.", pindex)
      return
   end
   if (players[pindex].nearby.category == 1 and next(players[pindex].nearby.ents) == nil) 
      or (players[pindex].nearby.category == 2 and next(players[pindex].nearby.resources) == nil) 
      or (players[pindex].nearby.category == 3 and next(players[pindex].nearby.containers) == nil) 
      or (players[pindex].nearby.category == 4 and next(players[pindex].nearby.buildings) == nil)
      or (players[pindex].nearby.category == 5 and next(players[pindex].nearby.vehicles) == nil)
      or (players[pindex].nearby.category == 6 and next(players[pindex].nearby.players) == nil)
      or (players[pindex].nearby.category == 7 and next(players[pindex].nearby.enemies) == nil)
      or (players[pindex].nearby.category == 8 and next(players[pindex].nearby.other) == nil) 
      then
      printout("No entities found.  Try refreshing with end key.", pindex)
   else
      local ents = {}
      if players[pindex].nearby.category == 1 then
         ents = players[pindex].nearby.ents
      elseif players[pindex].nearby.category == 2 then
         ents = players[pindex].nearby.resources
      elseif players[pindex].nearby.category == 3 then
         ents = players[pindex].nearby.containers
      elseif players[pindex].nearby.category == 4 then
         ents = players[pindex].nearby.buildings
      elseif players[pindex].nearby.category == 5 then
         ents = players[pindex].nearby.vehicles
      elseif players[pindex].nearby.category == 6 then
         ents = players[pindex].nearby.players
      elseif players[pindex].nearby.category == 7 then
         ents = players[pindex].nearby.enemies
      elseif players[pindex].nearby.category == 8 then
         ents = players[pindex].nearby.other
      end
      local ent = nil

      if ents[players[pindex].nearby.index].aggregate == false then
         --The scan target is an entity
         local i = 1
         --Remove invalid or unwanted instances of the entity
         while i <= #ents[players[pindex].nearby.index].ents do
            if ents[players[pindex].nearby.index].ents[i].valid and ents[players[pindex].nearby.index].ents[i].name ~= "highlight-box" 
               and ents[players[pindex].nearby.index].ents[i].type ~= "flying-text" then
               i = i + 1
            else
               table.remove(ents[players[pindex].nearby.index].ents, i)
               if players[pindex].nearby.selection > i then
                  players[pindex].nearby.selection = players[pindex].nearby.selection - 1
               end
            end
         end
         --If there is none left of the entity, remove it
         if #ents[players[pindex].nearby.index].ents == 0 then
            table.remove(ents,players[pindex].nearby.index)
            players[pindex].nearby.index = math.min(players[pindex].nearby.index, #ents)
            scan_index(pindex)
            return
         end
         --Sort by distance to player pos while describing indexed entries
         table.sort(ents[players[pindex].nearby.index].ents, function(k1, k2) 
            local pos = players[pindex].position
            return squared_distance(pos, k1.position) < squared_distance(pos, k2.position)
         end)
         if players[pindex].nearby.selection > #ents[players[pindex].nearby.index].ents then
            players[pindex].selection = 1
         end
         --The scan target is an entity, select it now
         ent = ents[players[pindex].nearby.index].ents[players[pindex].nearby.selection]
         if ent == nil then
            printout("Error: This object no longer exists. Try rescanning.", pindex)
            return
         end
         if not ent.valid then
            printout("Error: This object is no longer valid. Try rescanning.", pindex)
            return
         end
         players[pindex].cursor_pos = center_of_tile(ent.position)
         cursor_highlight(pindex, ent, "train-visualization")
         players[pindex].last_indexed_ent = ent
      else
         --The scan target is an aggregate
         if players[pindex].nearby.selection > #ents[players[pindex].nearby.index].ents then
            players[pindex].selection = 1
         end
         local name = ents[players[pindex].nearby.index].name
         local entry = ents[players[pindex].nearby.index].ents[players[pindex].nearby.selection]
         --If there is none left of the entry or it is an unwanted type (does this ever happen?), remove it
         if table_size(entry) == 0 or name == "highlight-box" then
            table.remove(ents[players[pindex].nearby.index].ents, players[pindex].nearby.selection)
            players[pindex].nearby.selection = players[pindex].nearby.selection - 1
            scan_index(pindex)
            return
         end
         --The scan target is an aggregate, select it now
         ent = {name = name, position = table.deepcopy(entry.position), group = entry.group} --maybe use "aggregate = true" ?
         players[pindex].cursor_pos = center_of_tile(ent.position)
         cursor_highlight(pindex, nil, "train-visualization")
         players[pindex].last_indexed_ent = ent
      end
      
      if not ents[players[pindex].nearby.index].aggregate and not ent.valid then
         printout("Error: Invalid object, maybe try rescanning.", pindex)
         return
      end
      
      refresh_player_tile(pindex)
      
      local dir_dist = dir_dist_locale(players[pindex].position, ent.position)
      if players[pindex].nearby.count == false then
         --Read the entity in terms of distance and direction
         local result={"access.thing-producing-listpos-dirdist",ent_name_locale(ent)}
         table.insert(result,extra_info_for_scan_list(ent,pindex,true))
         table.insert(result,{"description.of", players[pindex].nearby.selection , #ents[players[pindex].nearby.index].ents})--"X of Y"
         table.insert(result,dir_dist)
         printout(result,pindex)
      else
         --Read the entity in terms of count, and give the direction and distance of an example
         printout({"access.item_and_quantity-example-at-dirdist",
            {"access.item-quantity",ent_name_locale(ent),ents[players[pindex].nearby.index].count},
            dir_dist} , pindex)
      end
   end
end 

function scan_down(pindex)
   if players[pindex].in_menu then
      --These keys may overlap a lot so might as well
      return
   end
   if (players[pindex].nearby.category == 1 and players[pindex].nearby.index < #players[pindex].nearby.ents) or 
      (players[pindex].nearby.category == 2 and players[pindex].nearby.index < #players[pindex].nearby.resources) or 
      (players[pindex].nearby.category == 3 and players[pindex].nearby.index < #players[pindex].nearby.containers) or 
      (players[pindex].nearby.category == 4 and players[pindex].nearby.index < #players[pindex].nearby.buildings)  or 
      (players[pindex].nearby.category == 5 and players[pindex].nearby.index < #players[pindex].nearby.vehicles)  or 
      (players[pindex].nearby.category == 6 and players[pindex].nearby.index < #players[pindex].nearby.players)  or 
      (players[pindex].nearby.category == 7 and players[pindex].nearby.index < #players[pindex].nearby.enemies)  or 
      (players[pindex].nearby.category == 8 and players[pindex].nearby.index < #players[pindex].nearby.other) then
      players[pindex].nearby.index = players[pindex].nearby.index + 1
      players[pindex].nearby.selection = 1
   else 
      game.get_player(pindex).play_sound{path = "player-mine"}
      players[pindex].nearby.selection = 1
   end
--   if not(pcall(function()
      scan_index(pindex)
--   end)) then
--      if players[pindex].nearby.category == 1 then
--         table.remove(players[pindex].nearby.ents, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 2 then
--         table.remove(players[pindex].nearby.resources, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 3 then
--         table.remove(players[pindex].nearby.containers, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 4 then
--         table.remove(players[pindex].nearby.buildings, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 5 then
--         table.remove(players[pindex].nearby.vehicles, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 6 then
--         table.remove(players[pindex].nearby.players, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 7 then
--         table.remove(players[pindex].nearby.enemies, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 8 then
--         table.remove(players[pindex].nearby.other, players[pindex].nearby.index)
--      end
--      scan_up(pindex)
--      scan_down(pindex)
--   end
end

function scan_up(pindex)
   if players[pindex].in_menu then
      --These keys may overlap a lot so might as well
      return
   end
   if players[pindex].nearby.index > 1 then
      players[pindex].nearby.index = players[pindex].nearby.index - 1
      players[pindex].nearby.selection = 1
   elseif players[pindex].nearby.index <= 1 then
      players[pindex].nearby.index = 1
      players[pindex].nearby.selection = 1
      game.get_player(pindex).play_sound{path = "player-mine"}
   end
--   if not(pcall(function()
   scan_index(pindex)
--end)) then
--      if players[pindex].nearby.category == 1 then
--         table.remove(players[pindex].nearby.ents, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 2 then
--         table.remove(players[pindex].nearby.resources, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 3 then
--         table.remove(players[pindex].nearby.containers, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 4 then
--         table.remove(players[pindex].nearby.buildings, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 5 then
--         table.remove(players[pindex].nearby.vehicles, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 6 then
--         table.remove(players[pindex].nearby.players, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 7 then
--         table.remove(players[pindex].nearby.enemies, players[pindex].nearby.index)
--      elseif players[pindex].nearby.category == 8 then
--         table.remove(players[pindex].nearby.other, players[pindex].nearby.index)
--      end
--      scan_down(pindex)
--      scan_up(pindex)
--   end
 end

function scan_middle(pindex)
   if players[pindex].in_menu then
      --These keys may overlap a lot so might as well
      return
   end
   local ents = {}
   if players[pindex].nearby.category == 1 then
      ents = players[pindex].nearby.ents
   elseif players[pindex].nearby.category == 2 then
      ents = players[pindex].nearby.resources
   elseif players[pindex].nearby.category == 3 then
      ents = players[pindex].nearby.containers
   elseif players[pindex].nearby.category == 4 then
      ents = players[pindex].nearby.buildings
   elseif players[pindex].nearby.category == 5 then
      ents = players[pindex].nearby.vehicles
   elseif players[pindex].nearby.category == 6 then
      ents = players[pindex].nearby.players
   elseif players[pindex].nearby.category == 7 then
      ents = players[pindex].nearby.enemies
   elseif players[pindex].nearby.category == 8 then
      ents = players[pindex].nearby.other
   end

   if players[pindex].nearby.index < 1 then
      players[pindex].nearby.index = 1
   elseif players[pindex].nearby.index > #ents then
      players[pindex].nearby.index = #ents
   end

   if not(pcall(function()
      scan_index(pindex)
   end)) then
      table.remove(ents, players[pindex].nearby.index)
      scan_middle(pindex)
   end
 end

function rescan(pindex,filter_dir)
   players[pindex].nearby.index = 1
   players[pindex].nearby.selection = 1
   first_player = game.get_player(pindex)
   players[pindex].nearby.ents = scan_area(math.floor(players[pindex].cursor_pos.x)-2500, math.floor(players[pindex].cursor_pos.y)-2500, 5000, 5000, pindex, filter_dir)
   populate_categories(pindex)
   players[pindex].nearby.index = 1
   players[pindex].nearby.selection = 1
end


function index_of_entity(array, value)
   if next(array) == nil then
      return nil
   end
    for i = 1, #array,1 do
        if array[i].name == value then
            return i
      end
   end
   return nil
end

--The entity scanner runs here
function scan_area(x,y,w,h, pindex, filter_direction)
   local first_player = game.get_player(pindex)
   local surf = first_player.surface
   local ents = surf.find_entities_filtered{area = {{x, y},{x+w, y+h}}, type = {"resource", "tree", "highlight-box", "flying-text"}, invert = true} --Get all ents in the area except for these types
   local result = {}
   local pos = players[pindex].position
   local forest_density = nil
   local close_object_limit = 20.1
   
   --Find the nearest edges of already-loaded resource groups according to player pos, and insert them to the initial list as aggregates
   for name, resource in pairs(players[pindex].resources) do
      --Insert scanner entries 
      table.insert(result, {name = name, count = table_size(players[pindex].resources[name].patches), ents = {}, aggregate = true})
      --Insert instances for the entry
      local index = #result
      for group, patch in pairs(resource.patches) do
         local nearest_edge = nearest_edge(patch.edges, pos, name)
         --Filter check 1: Is the entity in the filter diection? (If a filter is set at all)
         local dir_of_ent = get_direction_of_that_from_this(nearest_edge,pos)
         local filter_passed = (filter_direction == nil or filter_direction == dir_of_ent)
         if not filter_passed then
            --Filter check 2: Is the entity nearby and almost within the filter diection?
            if util.distance(nearest_edge,pos) < close_object_limit then
               local new_dir_of_ent = get_balanced_direction_of_that_from_this(nearest_edge,pos)--Check with less bias towards diagonal directions to preserve 135 degrees FOV
               local CW_dir = (filter_direction + 1) % (2 * dirs.south)
               local CCW_dir = (filter_direction - 1) % (2 * dirs.south)
               filter_passed = (new_dir_of_ent == filter_direction or new_dir_of_ent == CW_dir or new_dir_of_ent == CCW_dir)
            end
         end
         if filter_passed then 
            --If it is a forest, check density
            if name == "forest" then
               local forest_pos = nearest_edge
               forest_density = classify_forest(forest_pos,pindex,false)
            else
               forest_density = nil
            end
            --Insert to the list if this group is not a forest at all, or not an empty or tiny forest
            if forest_density == nil or (forest_density ~= "empty" and forest_density ~= "patch") then 
               table.insert(result[index].ents, {group = group, position = nearest_edge})
            end
         end
      end
      --Remove empty entries
      if result[index].ents == nil or result[index].ents == {} or result[index].ents[1] == nil then
         table.remove(result,index)
      end
   end

   --Insert entities to the initial list
   for i=1, #ents, 1 do
      local extra_entry_info = extra_info_for_scan_list(ents[i],pindex,false)
      local scan_entry = ents[i].name .. extra_entry_info
      local index = index_of_entity(result, scan_entry)
      
      --Filter check 1: Is the entity in the filter diection? (If a filter is set at all)
      local dir_of_ent = get_direction_of_that_from_this(ents[i].position,pos)
      local filter_passed = (filter_direction == nil or filter_direction == dir_of_ent)
      if not filter_passed then
         --Filter check 2: Is the entity nearby and almost within the filter diection?
         if util.distance(ents[i].position,pos) < close_object_limit then
            local new_dir_of_ent = get_balanced_direction_of_that_from_this(ents[i].position,pos)--Check with less bias towards diagonal directions to preserve 135 degrees FOV
            local CW_dir = (filter_direction + 1) % (2 * dirs.south)
            local CCW_dir = (filter_direction - 1) % (2 * dirs.south)
            filter_passed = (new_dir_of_ent == filter_direction or new_dir_of_ent == CW_dir or new_dir_of_ent == CCW_dir)
         end
      end

      if filter_passed then 
         if index == nil then --The entry is not already indexed, so add a new entry line to the list
            table.insert(result, {name = scan_entry, count = 1, ents = {ents[i]}, aggregate = false}) 

         elseif #result[index] >= 100 then --If there are more than 100 instanes of this specific entry (?), replace a random one of them to add this
            table.remove(result[index].ents, math.random(100))
            table.insert(result[index].ents, ents[i])
            result[index].count = result[index].count + 1

         else
            table.insert(result[index].ents, ents[i]) --Add this ent as another instance of the entry
            result[index].count = result[index].count + 1        
   --         result[index] = ents[i]
         end
      end
   end
   
   --Sort the list
   if players[pindex].nearby.count == false then
      --Sort results by distance to player position when first creating the scanner list
      table.sort(result, function(k1, k2) 
         local pos = players[pindex].position
         local ent1 = nil
         local ent2 = nil
         if k1.aggregate then
               table.sort( k1.ents , function(k3, k4) 
                  return squared_distance(pos, k3.position) < squared_distance(pos, k4.position)
               end)
               ent1 = k1.ents[1]
--            end
         else
            ent1 = surf.get_closest(pos, k1.ents)
         end
         if k2.aggregate then
               table.sort( k2.ents , function(k3, k4) 
                  return squared_distance(pos, k3.position) < squared_distance(pos, k4.position)
               end)
               ent2 = k2.ents[1]
--            end
         else
         ent2 = surf.get_closest(pos, k2.ents)
         end
         return distance(pos, ent1.position) < distance(pos, ent2.position)
      end)

   else
      --Sort results by count
      table.sort(result, function(k1, k2)
         return k1.count > k2.count
      end)
   end
   return result

end

function toggle_cursor(pindex)
   if not players[pindex].cursor and not players[pindex].hide_cursor then
      players[pindex].cursor = true
      players[pindex].build_lock = false
      players[pindex].cursor_pos = center_of_tile(players[pindex].cursor_pos)
      move_cursor_map(players[pindex].cursor_pos,pindex)
      if not players[pindex].vanilla_mode then game.get_player(pindex).game_view_settings.update_entity_selection = false end
      read_tile(pindex, "Cursor mode enabled, ")
   else
      --printout("Cursor mode disabled", pindex)
      players[pindex].cursor = false
      game.get_player(pindex).game_view_settings.update_entity_selection = true
      players[pindex].cursor_pos = offset_position(players[pindex].position,players[pindex].player_direction,1)
      players[pindex].cursor_pos = center_of_tile(players[pindex].cursor_pos)
      move_cursor_map(players[pindex].cursor_pos,pindex)
      sync_build_arrow(pindex)
      target(pindex)
      players[pindex].player_direction = game.get_player(pindex).character.direction
      players[pindex].build_lock = false
      read_tile(pindex, "Cursor mode disabled, ")
   end
   if players[pindex].cursor_size < 2 or not players[pindex].cursor then 
      cursor_highlight(pindex, nil, nil)
   else
      local scan_left_top = {math.floor(players[pindex].cursor_pos.x)-players[pindex].cursor_size,math.floor(players[pindex].cursor_pos.y)-players[pindex].cursor_size}
      local scan_right_bottom = {math.floor(players[pindex].cursor_pos.x)+players[pindex].cursor_size+1,math.floor(players[pindex].cursor_pos.y)+players[pindex].cursor_size+1}
      draw_area_as_cursor(scan_left_top,scan_right_bottom,pindex)
   end
end

function teleport_to_cursor(pindex, muted, ignore_enemies, return_cursor)
   local result = teleport_to_closest(pindex, players[pindex].cursor_pos, muted, ignore_enemies)
   if return_cursor then
      players[pindex].cursor_pos = players[pindex].position
   end
   return result
end

function jump_to_player(pindex)
   local first_player = game.get_player(pindex)
   players[pindex].cursor_pos.x = math.floor(first_player.position.x)+.5
   players[pindex].cursor_pos.y = math.floor(first_player.position.y) + .5
   read_coords(pindex, "Cursor returned ")
   if players[pindex].cursor_size < 2 then 
      cursor_highlight(pindex, nil, nil)
   else
      local scan_left_top = {math.floor(players[pindex].cursor_pos.x)-players[pindex].cursor_size,math.floor(players[pindex].cursor_pos.y)-players[pindex].cursor_size}
      local scan_right_bottom = {math.floor(players[pindex].cursor_pos.x)+players[pindex].cursor_size+1,math.floor(players[pindex].cursor_pos.y)+players[pindex].cursor_size+1}
      draw_area_as_cursor(scan_left_top,scan_right_bottom,pindex)
   end
end

function refresh_player_tile(pindex)
   local surf = game.get_player(pindex).surface
   local search_area = {{x=-0.5,y=-.5},{x=0.29,y=0.29}}
   local search_center = players[pindex].cursor_pos
   search_area[1]=add_position(search_area[1],search_center)
   search_area[2]=add_position(search_area[2],search_center)
   
   players[pindex].tile.ents = surf.find_entities_filtered{area = search_area, name={"highlight-box","flying-text"},invert = true}
   players[pindex].tile.index = #players[pindex].tile.ents == 0 and 0 or 1
   if not(pcall(function()
      players[pindex].tile.tile =  surf.get_tile(players[pindex].cursor_pos.x, players[pindex].cursor_pos.y).name
   end)) then
      return false
   end
   return true
end

function read_tile(pindex, start_text)   
   local result = start_text or ""
   if not refresh_player_tile(pindex) then
      printout(result .. "Tile out of range", pindex)
      return
   end
   local ent = get_selected_ent(pindex)
   if not ent then
      players[pindex].tile.previous = nil
      result = result .. players[pindex].tile.tile
      cursor_highlight(pindex, nil, nil)

   else--laterdo tackle the issue here where entities such as tree stumps block preview info 
      result = result .. ent_info(pindex, ent)
      cursor_highlight(pindex, nil, nil)
      if game.get_player(pindex).game_view_settings.update_entity_selection == false then
         game.get_player(pindex).game_view_settings.update_entity_selection = true--imperfect fix here for the cursor highlight not updating
         cursor_highlight(pindex, ent, nil)
      end
      --game.get_player(pindex).print(result)--
      players[pindex].tile.previous = ent
   end
   if not ent or ent.type == "resource" then--possible bug with the h box being a new tile ent
      local stack = game.get_player(pindex).cursor_stack
      --Run build preview checks
      if stack and stack.valid_for_read and stack.valid and stack.prototype.place_result ~= nil then
         result = result .. build_preview_checks_info(stack,pindex)
         --game.get_player(pindex).print(result)--
      end
   end
     
   --If the player is holding a cut or copy tool, every entity being read gets mined as soon as you read a new tile.
   local stack = game.get_player(pindex).cursor_stack
   if stack and stack.valid_for_read and stack.name == "cut-paste-tool" and not players[pindex].vanilla_mode then
      if ent and ent.valid then--not while loop, because it causes crashes
         local name = ent.name
         game.get_player(pindex).play_sound{path = "player-mine"}
         if try_to_mine_with_sound(ent,pindex) then
            result = result .. name .. " mined, "
         end
         --Second round, in case two entities are there. While loops do not work!
         ent = get_selected_ent(pindex)
         if ent and ent.valid and players[pindex].walk ~= 2 then--not while
            local name = ent.name
            game.get_player(pindex).play_sound{path = "player-mine"}
            if try_to_mine_with_sound(ent,pindex) then
               result = result .. name .. " mined, "
            end 
         end
      end
   end
   printout(result, pindex)
   --game.get_player(pindex).print(result)--**
end

--Cursor building preview checks. NOTE: Only 1 by 1 entities for now
function build_preview_checks_info(stack, pindex)
   if stack == nil or not stack.valid_for_read or not stack.valid then
      return "invalid stack"
   end
   local p = game.get_player(pindex)
   local surf = game.get_player(pindex).surface
   local pos = table.deepcopy(players[pindex].cursor_pos)
   local result = ""
   local build_dir = players[pindex].building_direction * dirs.east--laterdo get player building directions to match the official defines
   local ent_p = stack.prototype.place_result --it is an entity prototype!
   if ent_p == nil or not ent_p.valid then
      return "invalid entity"
   end
   
   --Notify before all else if surface/player cannot place this entity. laterdo extend this valid placement check by copying over build offset stuff
   if ent_p.tile_width <= 1 and ent_p.tile_height <= 1 and not surf.can_place_entity{name = stack.name, position = pos, direction = build_dir} then
      return " cannot place this here "
   end
   
   --For belt types, check if it would form a corner or junction here. Laterdo include underground exits.
   if ent_p.type == "transport-belt" then
      local ents_north = p.surface.find_entities_filtered{position = {x = pos.x+0 ,y = pos.y-1}, type = "transport-belt"}
		local ents_south = p.surface.find_entities_filtered{position = {x = pos.x+0 ,y = pos.y+1}, type = "transport-belt"}
		local ents_east  = p.surface.find_entities_filtered{position = {x = pos.x+1 ,y = pos.y+0}, type = "transport-belt"}
		local ents_west  = p.surface.find_entities_filtered{position = {x = pos.x-1 ,y = pos.y+0}, type = "transport-belt"}
      
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x+0 ,y = pos.y-1}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x+0 ,y = pos.y+1}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x-1 ,y = pos.y-0}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x+1 ,y = pos.y-0}, surface = p.surface, time_to_live = 30}

      if #ents_north > 0 or #ents_south > 0 or #ents_east > 0 or #ents_west > 0 then
         local sideload_count = 0
         local backload_count = 0
         local  outload_count = 0
         local this_dir = build_dir
         local outload_dir = nil
         
         --Find the outloading belt and its direction, if any 
         if this_dir == dirs.north and ents_north[1] ~= nil and ents_north[1].valid then
            rendering.draw_circle{color = {0.5, 0.5, 1},radius = 0.3,width = 2,target = ents_north[1].position,surface = ents_north[1].surface,time_to_live = 30}
            outload_dir = ents_north[1].direction
            outload_count = 1
         elseif this_dir == dirs.east and ents_east[1] ~= nil and ents_east[1].valid then
            rendering.draw_circle{color = {0.5, 0.5, 1},radius = 0.3,width = 2,target = ents_east[1].position,surface = ents_east[1].surface,time_to_live = 30}
            outload_dir = ents_east[1].direction
            outload_count = 1
         elseif this_dir == dirs.south and ents_south[1] ~= nil and ents_south[1].valid then
            rendering.draw_circle{color = {0.5, 0.5, 1},radius = 0.3,width = 2,target = ents_south[1].position,surface = ents_south[1].surface,time_to_live = 30}
            outload_dir = ents_south[1].direction
            outload_count = 1
         elseif this_dir == dirs.west and ents_west[1] ~= nil and ents_west[1].valid then
            rendering.draw_circle{color = {0.5, 0.5, 1},radius = 0.3,width = 2,target = ents_west[1].position,surface = ents_west[1].surface,time_to_live = 30}
            outload_dir = ents_west[1].direction
            outload_count = 1
         end
         
         --Find the backloading and sideloading belts, if any
         if ents_north[1] ~= nil and ents_north[1].valid and ents_north[1].direction == dirs.south then
            rendering.draw_circle{color = {1, 1, 0.2},radius = 0.2,width = 2,target = ents_north[1].position,surface = ents_north[1].surface,time_to_live = 30}
            if this_dir == dirs.east or this_dir == dirs.west then
               sideload_count = sideload_count + 1
            elseif this_dir == dirs.south then
               backload_count = 1
            end
         end
         
         if ents_south[1] ~= nil and ents_south[1].valid and ents_south[1].direction == dirs.north then
            rendering.draw_circle{color = {1, 1, 0.4},radius = 0.2,width = 2,target = ents_south[1].position,surface = ents_south[1].surface,time_to_live = 30}
            if this_dir == dirs.east or this_dir == dirs.west then
               sideload_count = sideload_count + 1
            elseif this_dir == dirs.north then
               backload_count = 1
            end
         end
         
         if ents_east[1] ~= nil and ents_east[1].valid and ents_east[1].direction == dirs.west then
            rendering.draw_circle{color = {1, 1, 0.6},radius = 0.2,width = 2,target = ents_east[1].position,surface = ents_east[1].surface,time_to_live = 30}
            if this_dir == dirs.north or this_dir == dirs.south then
               sideload_count = sideload_count + 1
            elseif this_dir == dirs.west then
               backload_count = 1
            end
         end
         
         if ents_west[1] ~= nil and ents_west[1].valid and ents_west[1].direction == dirs.east then
            rendering.draw_circle{color = {1, 1, 0.8},radius = 0.2,width = 2,target = ents_west[1].position,surface = ents_west[1].surface,time_to_live = 30}
            if this_dir == dirs.north or this_dir == dirs.south then
               sideload_count = sideload_count + 1
            elseif this_dir == dirs.east then
               backload_count = 1
            end
         end
            
         --Determine expected junction info
         if sideload_count + backload_count + outload_count > 0 then--Skips "unit" because it is obvious
            result = ", forms belt " .. transport_belt_junction_info(sideload_count, backload_count, outload_count, this_dir, outload_dir, true)
         end
      end
   end
   
   --For underground belts, state the potential neighbor: any neighborless matching underground of the same name and same/opposite direction, and along the correct axis
	if ent_p.type == "underground-belt" then
      local connected = false
      local check_dist = 5
		if stack.name == "fast-underground-belt" then
		   check_dist = 7
		elseif stack.name == "express-underground-belt" then
		   check_dist = 9
		end
      local candidates = game.get_player(pindex).surface.find_entities_filtered{ name = stack.name, position = pos, radius = check_dist, direction = rotate_180(build_dir) } 
		if #candidates > 0 then
		   for i,cand in ipairs(candidates) do
			   rendering.draw_circle{color = {1, 1, 0},radius = 0.5,width = 3,target = cand.position,surface = cand.surface,time_to_live = 60}
            local dist_x = cand.position.x - pos.x
            local dist_y = cand.position.y - pos.y
			   if cand.direction == rotate_180(build_dir)
			   and (get_direction_of_that_from_this(cand.position,pos) == build_dir) and (dist_x == 0 or dist_y == 0) then
			      rendering.draw_circle{color = {0, 1, 0},radius = 1.0,width = 3,target = cand.position,surface = cand.surface,time_to_live = 60}
               result = result .. " connects " .. direction_lookup(build_dir) .. " with " .. math.floor(util.distance(cand.position,pos)) - 1 .. " tiles underground, "
               connected = true
			   end
         end			
		end
      if not connected then
         result = result .. " not connected "
      end
   end
   
   --For pipes to ground, state when connected 
   if stack.name == "pipe-to-ground" then
      local connected = false
      local check_dist = 10
      local candidates = game.get_player(pindex).surface.find_entities_filtered{ name = stack.name, position = pos, radius = check_dist, direction = rotate_180(build_dir) } 
		if #candidates > 0 then
		   for i,cand in ipairs(candidates) do
			   rendering.draw_circle{color = {1, 1, 0},radius = 0.5,width = 3,target = cand.position,surface = cand.surface,time_to_live = 60}
            local dist_x = cand.position.x - pos.x
            local dist_y = cand.position.y - pos.y
			   if cand.direction == rotate_180(build_dir)
			   and (get_direction_of_that_from_this(pos,cand.position) == build_dir) and (dist_x == 0 or dist_y == 0) then
			      rendering.draw_circle{color = {0, 1, 0},radius = 1.0,width = 3,target = cand.position,surface = cand.surface,time_to_live = 60}
               result = result .. " connects " .. direction_lookup(rotate_180(build_dir)) .. " with " .. math.floor(util.distance(cand.position,pos)) - 1 .. " tiles underground, "
               connected = true
			   end
         end			
		end
      if not connected then
         result = result .. " not connected underground, "
      end
   end
   
   --For pipes, read the fluids in fluidboxes of surrounding entities, if any. Also warn if there are multiple fluids, hence a mixing error.
   if stack.name == "pipe" then
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x+0 ,y = pos.y-1}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x+0 ,y = pos.y+1}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x-1 ,y = pos.y-0}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = pos.x+1 ,y = pos.y-0}, surface = p.surface, time_to_live = 30}
      local ents_north = p.surface.find_entities_filtered{position = {x = pos.x+0, y = pos.y-1} }
      local ents_south = p.surface.find_entities_filtered{position = {x = pos.x+0, y = pos.y+1} }
      local ents_east  = p.surface.find_entities_filtered{position = {x = pos.x+1, y = pos.y+0} }
      local ents_west  = p.surface.find_entities_filtered{position = {x = pos.x-1, y = pos.y+0} }
      local relevant_fluid_north = nil
      local relevant_fluid_east  = nil
      local relevant_fluid_south = nil
      local relevant_fluid_west  = nil
      
      if ents_north[1] ~= nil and ents_north[1].valid and ents_north[1].fluidbox ~= nil then
         rendering.draw_circle{color = {1, 1, 0},radius = 0.2,width = 2,target = ents_north[1].position, surface = p.surface, time_to_live = 30} 
         --Run checks to see if we have any fluidboxes that are relevant
         for i = 1, #ents_north[1].fluidbox, 1 do
            --p.print("box " .. i .. ": " .. ents_north[1].fluidbox[i].name)
            for j, con in ipairs(ents_north[1].fluidbox.get_pipe_connections(i)) do
               local target_pos = con.target_position 
               --p.print("new connection at: " .. target_pos.x .. "," .. target_pos.y)
               rendering.draw_circle{color = {1, 0, 0},radius = 0.2,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
               if util.distance(target_pos, pos) < 0.3 and not (ents_north[1].name == "pipe-to-ground" and ents_north[1].direction == dirs.north) then
                  rendering.draw_circle{color = {0, 1, 0},radius = 0.3,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
                  if ents_north[1].fluidbox[i] ~= nil then
                     relevant_fluid_north = ents_north[1].fluidbox[i].name
                  elseif ents_north[1].fluidbox.get_locked_fluid(i) ~= nil then
                     relevant_fluid_north = ents_north[1].fluidbox.get_locked_fluid(i)
                  else
                     relevant_fluid_north = "empty pipe"
                  end
               end
            end
         end
      end
      
      if ents_south[1] ~= nil and ents_south[1].valid and ents_south[1].fluidbox ~= nil then
         rendering.draw_circle{color = {1, 1, 0},radius = 0.2,width = 2,target = ents_south[1].position, surface = p.surface, time_to_live = 30} 
         --Run checks to see if we have any fluidboxes that are relevant
         for i = 1, #ents_south[1].fluidbox, 1 do
            --p.print("box " .. i .. ": " .. ents_south[1].fluidbox[i].name)
            for j, con in ipairs(ents_south[1].fluidbox.get_pipe_connections(i)) do
               local target_pos = con.target_position 
               --p.print("new connection at: " .. target_pos.x .. "," .. target_pos.y)
               rendering.draw_circle{color = {1, 0, 0},radius = 0.2,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
               if util.distance(target_pos, pos) < 0.3 and not (ents_south[1].name == "pipe-to-ground" and ents_south[1].direction == dirs.south) then
                  rendering.draw_circle{color = {0, 1, 0},radius = 0.3,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
                  if ents_south[1].fluidbox[i] ~= nil then
                     relevant_fluid_south = ents_south[1].fluidbox[i].name
                  elseif ents_south[1].fluidbox.get_locked_fluid(i) ~= nil then
                     relevant_fluid_south = ents_south[1].fluidbox.get_locked_fluid(i)
                  else
                     relevant_fluid_south = "empty pipe"
                  end
               end
            end
         end
      end
      
      if ents_east[1] ~= nil and ents_east[1].valid and ents_east[1].fluidbox ~= nil then
         rendering.draw_circle{color = {1, 1, 0},radius = 0.2,width = 2,target = ents_east[1].position, surface = p.surface, time_to_live = 30} 
         --Run checks to see if we have any fluidboxes that are relevant
         for i = 1, #ents_east[1].fluidbox, 1 do
            --p.print("box " .. i .. ": " .. ents_east[1].fluidbox[i].name)
            for j, con in ipairs(ents_east[1].fluidbox.get_pipe_connections(i)) do
               local target_pos = con.target_position 
               --p.print("new connection at: " .. target_pos.x .. "," .. target_pos.y)
               rendering.draw_circle{color = {1, 0, 0},radius = 0.2,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
               if util.distance(target_pos, pos) < 0.3 and not (ents_east[1].name == "pipe-to-ground" and ents_east[1].direction == dirs.east) then
                  rendering.draw_circle{color = {0, 1, 0},radius = 0.3,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
                  if ents_east[1].fluidbox[i] ~= nil then
                     relevant_fluid_east = ents_east[1].fluidbox[i].name
                  elseif ents_east[1].fluidbox.get_locked_fluid(i) ~= nil then
                     relevant_fluid_east = ents_east[1].fluidbox.get_locked_fluid(i)
                  else
                     relevant_fluid_east = "empty pipe"
                  end
               end
            end
         end
      end
      
      if ents_west[1] ~= nil and ents_west[1].valid and ents_west[1].fluidbox ~= nil then
         rendering.draw_circle{color = {1, 1, 0},radius = 0.2,width = 2,target = ents_west[1].position, surface = p.surface, time_to_live = 30} 
         --Run checks to see if we have any fluidboxes that are relevant
         for i = 1, #ents_west[1].fluidbox, 1 do
            --p.print("box " .. i .. ": " .. ents_west[1].fluidbox[i].name)
            for j, con in ipairs(ents_west[1].fluidbox.get_pipe_connections(i)) do
               local target_pos = con.target_position 
               --p.print("new connection at: " .. target_pos.x .. "," .. target_pos.y)
               rendering.draw_circle{color = {1, 0, 0},radius = 0.2,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
               if util.distance(target_pos, pos) < 0.3 and not (ents_west[1].name == "pipe-to-ground" and ents_west[1].direction == dirs.west) then
                  rendering.draw_circle{color = {0, 1, 0},radius = 0.3,width = 2,target = target_pos, surface = p.surface, time_to_live = 30}
                  if ents_west[1].fluidbox[i] ~= nil then
                     relevant_fluid_west = ents_west[1].fluidbox[i].name
                  elseif ents_west[1].fluidbox.get_locked_fluid(i) ~= nil then
                     relevant_fluid_west = ents_west[1].fluidbox.get_locked_fluid(i)
                  else
                     relevant_fluid_west = "empty pipe"
                  end
               end
            end
         end
      end
      
      
      --Assuming empty fluidboxes return nil, we need to check if all none-nil boxes are equal...
      if relevant_fluid_north ~= nil or relevant_fluid_east ~= nil or relevant_fluid_south ~= nil or relevant_fluid_west ~= nil then
         local count = 0
         result = result .. ", pipe connects to "
         
         if relevant_fluid_north ~= nil then
            result = result .. relevant_fluid_north .. " at north, "
            count = count + 1
         end
         if relevant_fluid_east ~= nil then
            result = result .. relevant_fluid_east  .. " at east, "
            count = count + 1
         end
         if relevant_fluid_south ~= nil then
            result = result .. relevant_fluid_south .. " at south, "
            count = count + 1
         end
         if relevant_fluid_west ~= nil then
            result = result .. relevant_fluid_west  .. " at west, "
            count = count + 1
         end
         
         if relevant_fluid_north ~= nil and (relevant_fluid_north == relevant_fluid_south or relevant_fluid_north == relevant_fluid_east or relevant_fluid_north == relevant_fluid_west) then
            count = count - 1
         end
         if relevant_fluid_east ~= nil and (relevant_fluid_east == relevant_fluid_south or relevant_fluid_east == relevant_fluid_west) then
            count = count - 1
         end
         if relevant_fluid_south ~= nil and (relevant_fluid_south == relevant_fluid_west) then
            count = count - 1
         end
         
         if count > 1 then
            result = result .. " warning: there may be mixing fluids "
         end
      end
      
   end
   
   --For electric poles, report the directions of up to 5 wire-connectible electric poles that can connect
   if ent_p.type == "electric-pole" then
     local pole_dict = surf.find_entities_filtered{type = "electric-pole", position = pos, radius = ent_p.max_wire_distance}
	  local poles = {}
	  for i, v in pairs(pole_dict) do
	     if v.prototype.max_wire_distance ~= nil and v.prototype.max_wire_distance >= ent_p.max_wire_distance then --Select only the poles that can connect back
		    table.insert(poles, v)
		 end
	  end
	  if #poles > 0 then
	     --List the first 4 poles within range
		 result = result .. " connecting "
	     for i, pole in ipairs(poles) do
		    if i < 5 then
			   local dist = math.ceil(util.distance(pole.position,pos))
			   local dir = get_direction_of_that_from_this(pole.position,pos)
			   result = result .. dist .. " tiles " .. direction_lookup(dir) .. ", "
			end
	     end
	  else
	     --Notify if no connections and state nearest electric pole
	     result = result .. " not connected, "
		 local nearest_pole, min_dist = find_nearest_electric_pole(nil,false,50,surf,pos)
		 if min_dist == nil or min_dist >= 1000 then
		    result = result .. " no electric poles within 1000 tiles, "
		 else
		    local dir = get_direction_of_that_from_this(nearest_pole.position,pos)
		    result = result .. math.ceil(min_dist) .. " tiles " .. direction_lookup(dir) .. " to nearest electric pole, "
		 end
	  end
   end
   
   --For roboports, like electric poles, list possible neighbors (anything within 100 distx or 100 disty will be a neighbor
   if ent_p.name == "roboport" then
      local reach = 48.5
      local top_left = {x = math.floor(pos.x - reach), y = math.floor(pos.y - reach)}
      local bottom_right = {x = math.ceil(pos.x + reach), y = math.ceil(pos.y + reach)}
      local port_dict = surf.find_entities_filtered{type = "roboport", area = {top_left, bottom_right}}
      local ports = {}
      for i, v in pairs(port_dict) do
         table.insert(ports, v)
      end
      if #ports > 0 then
         --List the first 5 poles within range
         result = result .. " connecting "
         for i, port in ipairs(ports) do
            if i <= 5 then
               local dist = math.ceil(util.distance(port.position,pos))
               local dir = get_direction_of_that_from_this(port.position,pos)
               result = result .. dist .. " tiles " .. direction_lookup(dir) .. ", "
            end
         end
      else
         --Notify if no connections and state nearest roboport
         result = result .. " not connected, "
         local max_dist = 2000
         local nearest_port, min_dist = find_nearest_roboport(p.surface, p.position, max_dist)
         if min_dist == nil or min_dist >= max_dist then
            result = result .. " no other roboports poles within " .. max_dist .. " tiles, "
         else
            local dir = get_direction_of_that_from_this(nearest_port.position,pos)
            result = result .. math.ceil(min_dist) .. " tiles " .. direction_lookup(dir) .. " to nearest roboport, "
         end
      end
   end
   
   --For all electric powered entities, note whether powered, and from which direction. Otherwise report the nearest power pole.
   if ent_p.electric_energy_source_prototype ~= nil then
         local position = pos
         if players[pindex].cursor then
               position.x = position.x + math.ceil(2*ent_p.selection_box.right_bottom.x)/2 - .5
               position.y = position.y + math.ceil(2*ent_p.selection_box.right_bottom.y)/2 - .5
         elseif players[pindex].player_direction == defines.direction.north then
            if players[pindex].building_direction == 0 or players[pindex].building_direction == 2 then
               position.y = position.y + math.ceil(2* ent_p.selection_box.left_top.y)/2 + .5
            elseif players[pindex].building_direction == 1 or players[pindex].building_direction == 3 then
            position.y = position.y + math.ceil(2* ent_p.selection_box.left_top.x)/2 + .5
            end
         elseif players[pindex].player_direction == defines.direction.south then
            if players[pindex].building_direction == 0 or players[pindex].building_direction == 2 then
               position.y = position.y + math.ceil(2* ent_p.selection_box.right_bottom.y)/2 - .5
            elseif players[pindex].building_direction == 1 or players[pindex].building_direction == 3 then
               position.y = position.y + math.ceil(2* ent_p.selection_box.right_bottom.x)/2 - .5
            end
         elseif players[pindex].player_direction == defines.direction.west then
            if players[pindex].building_direction == 0 or players[pindex].building_direction == 2 then
               position.x = position.x + math.ceil(2* ent_p.selection_box.left_top.x)/2 + .5
            elseif players[pindex].building_direction == 1 or players[pindex].building_direction == 3 then
               position.x = position.x + math.ceil(2* ent_p.selection_box.left_top.y)/2 + .5
            end

         elseif players[pindex].player_direction == defines.direction.east then
            if players[pindex].building_direction == 0 or players[pindex].building_direction == 2 then
               position.x = position.x + math.ceil(2* ent_p.selection_box.right_bottom.x)/2 - .5
            elseif players[pindex].building_direction == 1 or players[pindex].building_direction == 3 then
               position.x = position.x + math.ceil(2* ent_p.selection_box.right_bottom.y)/2 - .5
            end
         end
         local dict = game.get_filtered_entity_prototypes{{filter = "type", type = "electric-pole"}}
         local poles = {}
         for i, v in pairs(dict) do
            table.insert(poles, v)
         end
         table.sort(poles, function(k1, k2) return k1.supply_area_distance < k2.supply_area_distance end)
         local check = false
		 local found_pole = nil
         for i, pole in ipairs(poles) do
            local names = {}
            for i1 = i, #poles, 1 do
               table.insert(names, poles[i1].name)
            end
			local supply_dist = pole.supply_area_distance
			if supply_dist > 15 then
			   supply_dist = supply_dist - 2
			end
            local area = {
               left_top = {(position.x + math.ceil(ent_p.selection_box.left_top.x) - supply_dist), (position.y + math.ceil(ent_p.selection_box.left_top.y) - supply_dist)},
               right_bottom = {(position.x + math.floor(ent_p.selection_box.right_bottom.x) + supply_dist), (position.y + math.floor(ent_p.selection_box.right_bottom.y) + supply_dist)},
               orientation = players[pindex].building_direction/4
           }--**laterdo "connected" check is a little buggy at the supply area edges, need to trim and tune, maybe re-enable direction based offset? The offset could be due to the pole width: 1 vs 2, maybe just make it more conservative? 
            local T = {
               area = area,
               name = names
            }
			local supplier_poles = surf.find_entities_filtered(T)
            if #supplier_poles > 0 then
               check = true
			   found_pole = supplier_poles[1]
               break
            end
         end
         if check then
            result = result .. " Power connected "
			if found_pole.valid then
			   local dist = math.ceil(util.distance(found_pole.position,pos))
			   local dir = get_direction_of_that_from_this(found_pole.position,pos)
			   result = result .. " from " .. dist .. " tiles " .. direction_lookup(dir) .. ", "
			end
         else
             result = result .. " Power Not Connected, "
			 --Notify if no connections and state nearest electric pole
			 local nearest_pole, min_dist = find_nearest_electric_pole(nil,false,50,surf,pos)
			 if min_dist == nil or min_dist >= 1000 then
				result = result .. " no electric poles within 1000 tiles, "
			 else
				local dir = get_direction_of_that_from_this(nearest_pole.position,pos)
				result = result .. math.ceil(min_dist) .. " tiles " .. direction_lookup(dir) .. " to nearest electric pole, "
			 end
         end
   end
   
   if players[pindex].cursor and util.distance(players[pindex].cursor_pos , players[pindex].position) > p.reach_distance + 2 then
      result = result .. ", cursor out of reach "
   end
   return result
end


--Read the current co-ordinates of the cursor on the map or in a menu. For crafting recipe and technology menus, it reads the ingredients / requirements instead.
function read_coords(pindex, start_phrase)
   start_phrase = start_phrase or ""
   local result = start_phrase
   local ent = players[pindex].building.ent
   local offset = 0
   if players[pindex].menu == "building" and players[pindex].building.recipe_list ~= nil then
      offset = 1
   end
   if not(players[pindex].in_menu) or players[pindex].menu == "structure-travel" or players[pindex].menu == "travel" then
      if players[pindex].vanilla_mode then
         players[pindex].cursor_pos = game.get_player(pindex).position
      end
      if game.get_player(pindex).driving then
         --Give vehicle coords and orientation and speed --laterdo find exact speed coefficient
         local vehicle = game.get_player(pindex).vehicle
         result = result .. " in " .. vehicle.name .. " " 
         if vehicle.speed > 0 then
            result = result .. " heading " .. get_heading(vehicle) .. " at " .. math.floor(vehicle.speed * 215) .. " kilometers per hour, past the point " 
         elseif vehicle.speed < 0 then
            result = result .. " facing" .. get_heading(vehicle) .. " while reversing at "  .. math.floor(-vehicle.speed * 215) .. " kilometers per hour, past the point " 
         else
            result = result .. " parked facing " .. get_heading(vehicle) .. " at point "
         end
         printout(result .. math.floor(vehicle.position.x) .. ", " .. math.floor(vehicle.position.y), pindex)
      else
         --Simply give coords
         local location = get_entity_part_at_cursor(pindex)
         if location == nil then
            location = " "
         end
         result = result .. " " .. location .. ", at " .. math.floor(players[pindex].cursor_pos.x) .. ", " .. math.floor(players[pindex].cursor_pos.y)
         game.get_player(pindex).print("At " ..  math.floor(players[pindex].cursor_pos.x) .. ", " .. math.floor(players[pindex].cursor_pos.y) , {volume_modifier = 0})
         rendering.draw_circle{color = {1, 0.2, 0},radius = 0.1,width = 5,target = players[pindex].cursor_pos,surface = game.get_player(pindex).surface,time_to_live = 180}
         
         --If there is a build preview, give its dimensions and which way they extend
         local stack = game.get_player(pindex).cursor_stack
         if stack and stack.valid_for_read and stack.valid and stack.prototype.place_result ~= nil and (stack.prototype.place_result.tile_height > 1 or stack.prototype.place_result.tile_width > 1) then
            local dir = players[pindex].building_direction * dirs.east
            local p_dir = players[pindex].player_direction
            local preview_str = ", preview is " 
            if dir == dirs.north or dir == dirs.south then 
               preview_str = preview_str .. stack.prototype.place_result.tile_width .. " wide " 
            elseif dir == dirs.east or dir == dirs.west then
               preview_str = preview_str .. stack.prototype.place_result.tile_height .. " wide " 
            end
            if players[pindex].cursor or p_dir == dirs.east or p_dir == dirs.south or p_dir == dirs.north then
               preview_str = preview_str .. " to the east "
            elseif not players[pindex].cursor and p_dir == dirs.west then
               preview_str = preview_str .. " to the west "
            end
            if dir == dirs.north or dir == dirs.south then 
               preview_str = preview_str .. " and " .. stack.prototype.place_result.tile_height .. " high " 
            elseif dir == dirs.east or dir == dirs.west then
               preview_str = preview_str .. " and " .. stack.prototype.place_result.tile_width .. " high " 
            end
            if players[pindex].cursor or p_dir == dirs.east or p_dir == dirs.south or p_dir == dirs.west then
               preview_str = preview_str .. " to the south "
            elseif not players[pindex].cursor and p_dir == dirs.north then
               preview_str = preview_str .. " to the north "
            end
            result = result .. preview_str
         elseif stack and stack.valid_for_read and stack.valid and stack.prototype.place_as_tile_result ~= nil then
            local preview_str = ", paving preview " 
            local player = players[pindex]
            preview_str = ", paving preview is " .. (player.cursor_size * 2 + 1) .. " by " .. (player.cursor_size * 2 + 1) .. " tiles, centered on this tile. "
            if player.cursor then
               --preview_str = ", paving preview extends " .. (player.cursor_size * 2 + 1) .. " east and " .. (player.cursor_size * 2 + 1) .. " south, starting from this tile. "
            end
         end
         printout(result,pindex)
      end
   elseif players[pindex].menu == "inventory" or (players[pindex].menu == "building" and players[pindex].building.sector > offset + #players[pindex].building.sectors) then
      --Give slot coords (player inventory)
      local x = players[pindex].inventory.index %10
      local y = math.floor(players[pindex].inventory.index/10) + 1
      if x == 0 then
         x = x + 10
         y = y - 1
      end
      printout(result .. x .. ", " .. y, pindex)
   elseif players[pindex].menu == "building" and players[pindex].building.recipe_selection == false then
      --Give slot coords (chest/building inventory)
      local x = -1 --Col number
      local y = -1 --Row number
      local row_length = players[pindex].preferences.building_inventory_row_length
      x = players[pindex].building.index % row_length
      y = math.floor(players[pindex].building.index / row_length) + 1
      if x == 0 then
         x = x + row_length
         y = y - 1
      end
      printout(result .. x .. ", " .. y, pindex)

   elseif players[pindex].menu == "crafting" then
      --Read recipe ingredients / products (crafting menu)
      local recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index]
      result = result .. "Ingredients: "
      for i, v in pairs(recipe.ingredients) do
         result = result .. ", " .. v.name .. " x" .. v.amount
      end
      result = result .. ", Products: "
      for i, v in pairs(recipe.products) do
         result = result .. ", " .. v.name .. " x" .. v.amount
      end
      result = result .. ", time " .. recipe.energy .. " seconds by default."
      printout(result, pindex)

   elseif players[pindex].menu == "technology" then
      --Read research requirements
      local techs = {}
      if players[pindex].technology.category == 1 then
         techs = players[pindex].technology.lua_researchable
      elseif players[pindex].technology.category == 2 then
         techs = players[pindex].technology.lua_locked
      elseif players[pindex].technology.category == 3 then
         techs = players[pindex].technology.lua_unlocked
      end
   
      if next(techs) ~= nil and players[pindex].technology.index > 0 and players[pindex].technology.index <= #techs then
         result = result .. "Requires "
         local dict = techs[players[pindex].technology.index].prerequisites 
         local pre_count = 0
         for a, b in pairs(dict) do
            pre_count = pre_count + 1
         end
         if pre_count == 0 then
            result = result .. " No prior research "
         end
         for i, preq in pairs(techs[players[pindex].technology.index].prerequisites) do 
            result = result .. preq.name .. " , "
         end
         result = result .. " and " .. techs[players[pindex].technology.index].research_unit_count .. " x "
         for i, ingredient in pairs(techs[players[pindex].technology.index].research_unit_ingredients ) do
            result = result .. ingredient.name .. " " .. " , "
         end
         
         printout(result, pindex)
      end
   end
   if players[pindex].menu == "building" and players[pindex].building.recipe_selection then
      --Read recipe ingredients / products (building recipe selection)
      local recipe = players[pindex].building.recipe_list[players[pindex].building.category][players[pindex].building.index]
      result = result .. "Ingredients: "
      for i, v in pairs(recipe.ingredients) do
         result = result .. ", " .. v.name .. " x" .. v.amount
      end
      result = result .. ", products: "
      for i, v in pairs(recipe.products) do
         result = result .. ", " .. v.name .. " x" .. v.amount
      end
      result = result .. ", time " .. recipe.energy .. " seconds by default."
      printout(result, pindex)
   end
end

function initialize(player)
   local force=player.force.index
   global.forces[force] = global.forces[force] or {}
   local fa_force=global.forces[force]

   global.players[player.index] = global.players[player.index] or {}
   local faplayer = global.players[player.index]
   faplayer.player = player
   
   if not fa_force.resources then
      for pi, p in pairs(global.players) do
         if p.player.valid and p.player.force.index == force and p.resources and p.mapped then
            fa_force.resources = p.resources
            fa_force.mapped = p.mapped
            break
         end
      end
      fa_force.resources = fa_force.resources or {}
      fa_force.mapped = fa_force.mapped or {}
   end
      
   local character = player.cutscene_character or player.character
   faplayer.in_menu = faplayer.in_menu or false
   faplayer.in_item_selector = faplayer.in_item_selector or false
   faplayer.menu = faplayer.menu or "none"
   faplayer.entering_search_term = faplayer.entering_search_term or false
   faplayer.menu_search_index = faplayer.menu_search_index or nil
   faplayer.menu_search_index_2 = faplayer.menu_search_index_2 or nil
   faplayer.menu_search_term = faplayer.menu_search_term or nil
   faplayer.menu_search_frame = faplayer.menu_search_frame or nil
   faplayer.menu_search_last_name = faplayer.menu_search_last_name or nil
   faplayer.cursor = faplayer.cursor or false
   faplayer.cursor_size = faplayer.cursor_size or 0 
   faplayer.cursor_ent_highlight_box = faplayer.cursor_ent_highlight_box or nil
   faplayer.cursor_tile_highlight_box = faplayer.cursor_tile_highlight_box or nil
   faplayer.num_elements = faplayer.num_elements or 0
   faplayer.player_direction = faplayer.player_direction or character.walking_state.direction
   faplayer.position = faplayer.position or center_of_tile(character.position)
   faplayer.cursor_pos = faplayer.cursor_pos or offset_position(faplayer.position,faplayer.player_direction,1)
   faplayer.walk = faplayer.walk or 0
   faplayer.move_queue = faplayer.move_queue or {}
   faplayer.building_direction = faplayer.building_direction or 0 --Values are 0,1,2,3 for N,E,S,W
   faplayer.building_footprint = faplayer.building_footprint or nil
   faplayer.building_direction_arrow = faplayer.building_direction_arrow or nil
   faplayer.overhead_sprite = nil
   faplayer.overhead_circle = nil
   faplayer.custom_GUI_frame = nil
   faplayer.custom_GUI_sprite = nil
   faplayer.direction_lag = faplayer.direction_lag or true
   faplayer.previous_hand_item_name = faplayer.previous_hand_item_name or ""
   faplayer.last = faplayer.last or ""
   faplayer.last_indexed_ent = faplayer.last_indexed_ent or nil 
   faplayer.item_selection = faplayer.item_selection or false
   faplayer.item_cache = faplayer.item_cache or {}
   faplayer.zoom = faplayer.zoom or 1
   faplayer.build_lock = faplayer.build_lock or false
   faplayer.vanilla_mode = faplayer.vanilla_mode or false
   faplayer.hide_cursor = faplayer.hide_cursor or false
   faplayer.allow_reading_flying_text = faplayer.allow_reading_flying_text or true
   faplayer.resources = fa_force.resources
   faplayer.mapped = fa_force.mapped
   faplayer.destroyed = faplayer.destroyed or {}
   faplayer.last_menu_toggle_tick = faplayer.last_menu_toggle_tick or 1
   faplayer.last_menu_search_tick = faplayer.last_menu_search_tick or 1
   faplayer.last_click_tick = faplayer.last_click_tick or 1
   faplayer.last_damage_alert_tick = faplayer.last_damage_alert_tick or 1
   faplayer.last_damage_alert_pos = faplayer.last_damage_alert_pos or nil
   faplayer.last_pg_key_tick = faplayer.last_pg_key_tick or 1
   faplayer.last_honk_tick = faplayer.last_honk_tick or 1
   faplayer.last_pickup_tick = faplayer.last_pickup_tick or 1
   faplayer.last_item_picked_up = faplayer.last_item_picked_up or nil
   faplayer.skip_read_hand = faplayer.skip_read_hand or false

   faplayer.preferences = {
      building_inventory_row_length = building_inventory_row_length or 8,
      inventory_wraps_around = inventory_wraps_around or true,
      tiles_placed_from_northwest_corner = tiles_placed_from_northwest_corner or false
   }
   
   faplayer.nearby = faplayer.nearby or {
      index = 0,
      selection = 0,
      count = false,
      category = 1,
      ents = {},
      resources = {},
      containers = {},
      buildings = {},
      vehicles = {},
      players = {},
      enemies = {},
      other = {}
   }
   faplayer.nearby.ents = faplayer.nearby.ents or {}

   faplayer.tile = faplayer.tile or {
      ents = {},
      tile = "",
      index = 1,
      previous = nil
   }

   faplayer.inventory = faplayer.inventory or {
      lua_inventory = nil,
      max = 0,
      index = 1
   }

   faplayer.crafting = faplayer.crafting or {
      lua_recipes = nil,
      max = 0,
      index = 1,
      category = 1
   }

   faplayer.crafting_queue = faplayer.crafting_queue or {
      index = 1,
      max = 0,
      lua_queue = nil
   }

   faplayer.technology = faplayer.technology or {
      index = 1,
      category = 1,
      lua_researchable = {},
      lua_unlocked = {},
      lua_locked = {}
   }

   faplayer.building = faplayer.building or {
      index = 0,
      ent = nil,
      sectors = nil,
      sector = 0,
      recipe_selection = false,
      item_selection = false,
      category = 0,
      recipe = nil,
      recipe_list = nil
   }

   faplayer.belt = faplayer.belt or {
      index = 1,
      sector = 1,
      ent = nil,
      line1 = nil,
      line2 = nil,
      network = {},
      side = 0
   }
   faplayer.warnings = faplayer.warnings or {
      short = {},
      medium = {},
      long = {},
      sector = 1,
      index = 1,
      category = 1
   }
   faplayer.pump = faplayer.pump or {
      index = 0,
      positions = {}
   }

   faplayer.item_selector = faplayer.item_selector or {
      index = 0,
      group = 0,
      subgroup = 0
   }

   faplayer.travel = faplayer.travel or {
      index = {x = 1, y = 0},
      creating = false,
      renaming = false
   }

   faplayer.structure_travel = faplayer.structure_travel or {
      network = {},
      current = nil,
      index = 0,
      direction = "none"
   }
   
   faplayer.rail_builder = faplayer.rail_builder or {
      index = 0,
      index_max = 1,
      rail = nil,
      rail_type = 0
   }
   
   faplayer.train_menu = faplayer.train_menu or {
      index = 0,
      renaming = false,
      locomotive = nil,
      wait_time = 300,
      index_2 = 0,
      selecting_station = false
   }
   
   faplayer.train_stop_menu = faplayer.train_stop_menu or {
      index = 0,
      renaming = false,
      stop = nil,
      wait_condition = "time",
      wait_time_seconds = 30,
      safety_wait_enabled = true
   }
   
   faplayer.valid_train_stop_list = faplayer.valid_train_stop_list or {}
   
   faplayer.roboport_menu = faplayer.roboport_menu or {
      port = nil,
      index = 0,
      renaming = false
   }

   if table_size(faplayer.mapped) == 0 then
      player.force.rechart()
   end
   
   faplayer.localisations = faplayer.localisations or {} 
   faplayer.translation_id_lookup = faplayer.translation_id_lookup or {}
   localising.request_all_the_translations(player.index)
   
   faplayer.bump = faplayer.bump or {
      last_bump_tick = 1,     --Updated in bump checker
      last_dir_key_tick = 1,  --Updated in key press handlers
      last_dir_key_1st = nil, --Updated in key press handlers
      last_dir_key_2nd = nil, --Updated in key press handlers
      last_pos_1 = nil,       --Updated in bump checker
      last_pos_2 = nil,       --Updated in bump checker
      last_pos_3 = nil,       --Updated in bump checker
      last_pos_4 = nil,       --Updated in bump checker
      last_dir_2 = nil,       --Updated in bump checker
      last_dir_1 = nil        --Updated in bump checker
      }
   
end


script.on_event(defines.events.on_player_changed_position,function(event)
      local pindex = event.player_index
      if not check_for_player(pindex) then
         return
      end
      if players[pindex].walk == 2 then
         local pos = center_of_tile(game.get_player(pindex).position)
         if game.get_player(pindex).walking_state.direction ~= players[pindex].direction then 
            -- turn 
            players[pindex].direction = game.get_player(pindex).walking_state.direction
            players[pindex].player_direction = game.get_player(pindex).walking_state.direction
            local new_pos = center_of_tile(offset_position(pos,players[pindex].direction,1))
            players[pindex].cursor_pos = new_pos
            players[pindex].position = pos
            cursor_highlight(pindex, nil, nil)
            sync_build_arrow(pindex)
            players[pindex].cursor_pos = center_of_tile(players[pindex].cursor_pos)
            if not players[pindex].vanilla_mode then
               target(pindex)
            end

            --Rotate belts in hand for build lock Mode
            local stack = game.get_player(pindex).cursor_stack
            if players[pindex].build_lock and stack.valid_for_read and stack.valid and stack.prototype.place_result ~= nil and stack.prototype.place_result.type == "transport-belt" then 
               players[pindex].building_direction = math.floor(game.get_player(pindex).walking_state.direction / dirs.east)
            end
         else
            --Walk straight
            players[pindex].cursor_pos.x = players[pindex].cursor_pos.x + pos.x - players[pindex].position.x
            players[pindex].cursor_pos.y = players[pindex].cursor_pos.y + pos.y - players[pindex].position.y
            players[pindex].cursor_pos = center_of_tile(players[pindex].cursor_pos) 
            if not players[pindex].vanilla_mode then
               target(pindex) 
            end
            players[pindex].position = pos
            
            cursor_highlight(pindex, nil, nil)
            sync_build_arrow(pindex)
            
            if players[pindex].build_lock then
               build_item_in_hand(pindex, -2)
            end
         end
         
         --Name a detected entity that you can or cannot walk on, or a tile you cannot walk on
         refresh_player_tile(pindex)
         local ent = get_selected_ent(pindex)
         if not players[pindex].vanilla_mode and ((ent ~= nil and ent.valid) or not game.get_player(pindex).surface.can_place_entity{name = "character", position = players[pindex].cursor_pos}) then
            target(pindex)
            if game.get_player(pindex).driving then
               return
            end
            read_tile(pindex)
         end
      end
end)



function menu_cursor_move(direction,pindex)
   players[pindex].preferences.inventory_wraps_around = true--laterdo make this a setting to toggle
   if     direction == defines.direction.north then
      menu_cursor_up(pindex)
   elseif direction == defines.direction.south then
      menu_cursor_down(pindex)
   elseif direction == defines.direction.east  then
      menu_cursor_right(pindex)
   elseif direction == defines.direction.west  then
      menu_cursor_left(pindex)
   end
end 

--menu_up
function menu_cursor_up(pindex)
   if players[pindex].item_selection then
      if players[pindex].item_selector.group == 0 then
         printout("Blank", pindex)
      elseif players[pindex].item_selector.subgroup == 0 then
         players[pindex].item_cache = get_iterable_array(game.item_group_prototypes)
         prune_item_groups(players[pindex].item_cache)
         players[pindex].item_selector.index = players[pindex].item_selector.group
         players[pindex].item_selector.group = 0
         read_item_selector_slot(pindex)
      else
         local group = players[pindex].item_cache[players[pindex].item_selector.index].group
         players[pindex].item_cache = get_iterable_array(group.subgroups)
         prune_item_groups(players[pindex].item_cache)

         players[pindex].item_selector.index = players[pindex].item_selector.subgroup
         players[pindex].item_selector.subgroup = 0
         read_item_selector_slot(pindex)
               end         

   elseif players[pindex].menu == "inventory" then
      players[pindex].inventory.index = players[pindex].inventory.index -10
      if players[pindex].inventory.index < 1 then
         if players[pindex].preferences.inventory_wraps_around == true then  
            --Wrap around setting: Move to the inventory end and read slot
            players[pindex].inventory.index = players[pindex].inventory.max + players[pindex].inventory.index
            game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
            read_inventory_slot(pindex)
         else 
            --Border setting: Undo change and play "wall" sound
            players[pindex].inventory.index = players[pindex].inventory.index +10
            game.get_player(pindex).play_sound{path = "player-mine"}
            printout("Border.", pindex)
         end
      else
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         read_inventory_slot(pindex)
      end      

   elseif players[pindex].menu == "crafting" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      players[pindex].crafting.index = 1
      players[pindex].crafting.category = players[pindex].crafting.category - 1

      if players[pindex].crafting.category < 1 then
         players[pindex].crafting.category = players[pindex].crafting.max
      end
      read_crafting_slot(pindex)
   elseif players[pindex].menu == "crafting_queue" then   
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      load_crafting_queue(pindex)
      players[pindex].crafting_queue.index = 1
      read_crafting_queue(pindex)
   elseif players[pindex].menu == "building" then
      --Move one row up in a building inventory of some kind
      if players[pindex].building.sector <= #players[pindex].building.sectors then
         --Most building sectors, eg. chest rows
         if players[pindex].building.sectors[players[pindex].building.sector].inventory == nil or #players[pindex].building.sectors[players[pindex].building.sector].inventory < 1 then
            printout("blank sector", pindex)
            return
         end
         --Move one row up in building inventory
         local row_length = players[pindex].preferences.building_inventory_row_length
         if #players[pindex].building.sectors[players[pindex].building.sector].inventory > row_length then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].building.index = players[pindex].building.index - row_length
            if players[pindex].building.index < 1 then 
               --Wrap around to building inventory last row
               game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
               players[pindex].building.index = players[pindex].building.index + #players[pindex].building.sectors[players[pindex].building.sector].inventory 
            end
         else
            --Inventory size < row length: Wrap over to the same slot
            game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
            --players[pindex].building.index = 1
         end
         read_building_slot(pindex,false)
      elseif players[pindex].building.recipe_list == nil then
         --Move one row up in player inventory
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].inventory.index = players[pindex].inventory.index -10
         if players[pindex].inventory.index < 1 then
            players[pindex].inventory.index = players[pindex].inventory.max + players[pindex].inventory.index
         end
         read_inventory_slot(pindex)
      else
         if players[pindex].building.sector == #players[pindex].building.sectors + 1 then
            --Last building sector. Case = ??? **
            if players[pindex].building.recipe_selection then
               game.get_player(pindex).play_sound{path = "Inventory-Move"}
               players[pindex].building.category = players[pindex].building.category - 1
               players[pindex].building.index = 1
               if players[pindex].building.category < 1 then
                  players[pindex].building.category = #players[pindex].building.recipe_list
               end
            end
            read_building_recipe(pindex)
         else
            --Case = ???
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].inventory.index = players[pindex].inventory.index -10
            if players[pindex].inventory.index < 1 then
               players[pindex].inventory.index = players[pindex].inventory.max + players[pindex].inventory.index
            end
            read_inventory_slot(pindex)
            end
         end
   elseif players[pindex].menu == "technology" then
      if players[pindex].technology.category > 1 then
         players[pindex].technology.category = players[pindex].technology.category - 1
         players[pindex].technology.index = 1
      end
      if players[pindex].technology.category == 1 then
         printout("Researchable ttechnologies", pindex)
      elseif players[pindex].technology.category == 2 then
         printout("Locked technologies", pindex)
      elseif players[pindex].technology.category == 3 then
         printout("Past Research", pindex)
      end
      
   elseif players[pindex].menu == "belt" then
      if players[pindex].belt.sector == 1 then
         if (players[pindex].belt.side == 1 and players[pindex].belt.line1.valid and players[pindex].belt.index > 1) or (players[pindex].belt.side == 2 and players[pindex].belt.line2.valid and players[pindex].belt.index > 1) then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = players[pindex].belt.index - 1
         end
      elseif players[pindex].belt.sector == 2 then
         local max = 0
         if players[pindex].belt.side == 1 then
            max = #players[pindex].belt.network.combined.left
         elseif players[pindex].belt.side == 2 then
            max = #players[pindex].belt.network.combined.right
         end
         if players[pindex].belt.index > 1 then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = math.min(players[pindex].belt.index - 1, max)
         end
      elseif players[pindex].belt.sector == 3 then
         local max = 0
         if players[pindex].belt.side == 1 then
            max = #players[pindex].belt.network.downstream.left
         elseif players[pindex].belt.side == 2 then
            max = #players[pindex].belt.network.downstream.right
         end
         if players[pindex].belt.index > 1 then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = math.min(players[pindex].belt.index - 1, max)
         end
      elseif players[pindex].belt.sector == 4 then
         local max = 0
         if players[pindex].belt.side == 1 then
            max = #players[pindex].belt.network.upstream.left
         elseif players[pindex].belt.side == 2 then
            max = #players[pindex].belt.network.upstream.right
         end
         if players[pindex].belt.index > 1 then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = math.min(players[pindex].belt.index - 1, max)
         end

      end
      read_belt_slot(pindex)
   elseif players[pindex].menu == "warnings" then
      if players[pindex].warnings.category > 1 then
         players[pindex].warnings.category = players[pindex].warnings.category - 1
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].warnings.index = 1
      end
      read_warnings_slot(pindex)
   elseif players[pindex].menu == "pump" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      players[pindex].pump.index = math.max(1, players[pindex].pump.index - 1)      
      local dir = ""
      if players[pindex].pump.positions[players[pindex].pump.index].direction == 0 then
         dir = " North"
      elseif players[pindex].pump.positions[players[pindex].pump.index].direction == 4 then
         dir = " South"
      elseif players[pindex].pump.positions[players[pindex].pump.index].direction == 2 then
         dir = " East"
      elseif players[pindex].pump.positions[players[pindex].pump.index].direction == 6 then
         dir = " West"
      end

      printout("Option " .. players[pindex].pump.index .. ": " .. math.floor(distance(game.get_player(pindex).position, players[pindex].pump.positions[players[pindex].pump.index].position)) .. " meters " .. direction(game.get_player(pindex).position, players[pindex].pump.positions[players[pindex].pump.index].position) .. " Facing " .. dir, pindex)
   elseif players[pindex].menu == "travel" then
      if players[pindex].travel.index.y > 1 then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].travel.index.y = players[pindex].travel.index.y - 1
      else
         players[pindex].travel.index.y = 1
         end
      players[pindex].travel.index.x = 1
      read_travel_slot(pindex)
   elseif players[pindex].menu == "structure-travel" then
      move_cursor_structure(pindex, 0)
   elseif players[pindex].menu == "rail_builder" then
      rail_builder_up(pindex)
   elseif players[pindex].menu == "train_stop_menu" then
      train_stop_menu_up(pindex)
   elseif players[pindex].menu == "roboport_menu" then
      roboport_menu_up(pindex)
   end
end


--menu_down
function menu_cursor_down(pindex)
   if players[pindex].item_selection then
      if players[pindex].item_selector.group == 0 then
         players[pindex].item_selector.group = players[pindex].item_selector.index
         players[pindex].item_cache = get_iterable_array(players[pindex].item_cache[players[pindex].item_selector.group].subgroups)
         prune_item_groups(players[pindex].item_cache)

         players[pindex].item_selector.index = 1
         read_item_selector_slot(pindex)
      elseif players[pindex].item_selector.subgroup == 0 then
         players[pindex].item_selector.subgroup = players[pindex].item_selector.index
         local prototypes = game.get_filtered_item_prototypes{{filter="subgroup",subgroup = players[pindex].item_cache[players[pindex].item_selector.index].name}}
         players[pindex].item_cache = get_iterable_array(prototypes)
         players[pindex].item_selector.index = 1
         read_item_selector_slot(pindex)
      else
         printout("Press left bracket to confirm your selection.", pindex)
               end         

   elseif players[pindex].menu == "inventory" then
      players[pindex].inventory.index = players[pindex].inventory.index +10
      if players[pindex].inventory.index > players[pindex].inventory.max then
         if players[pindex].preferences.inventory_wraps_around == true then  
            --Wrap around setting: Wrap over to first row
            players[pindex].inventory.index = players[pindex].inventory.index % 10
            if players[pindex].inventory.index == 0 then
               players[pindex].inventory.index = 10
            end
            game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
            read_inventory_slot(pindex)
         else 
            --Border setting: Undo change and play "wall" sound
            players[pindex].inventory.index = players[pindex].inventory.index -10
            game.get_player(pindex).play_sound{path = "player-mine"}
            printout("Border.", pindex)
         end
      else
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         read_inventory_slot(pindex)
      end

   elseif players[pindex].menu == "crafting" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      players[pindex].crafting.index = 1
      players[pindex].crafting.category = players[pindex].crafting.category + 1

      if players[pindex].crafting.category > players[pindex].crafting.max then
         players[pindex].crafting.category = 1
      end
      read_crafting_slot(pindex)
   elseif players[pindex].menu == "crafting_queue" then   
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      load_crafting_queue(pindex)
      players[pindex].crafting_queue.index = players[pindex].crafting_queue.max
      read_crafting_queue(pindex)
   elseif players[pindex].menu == "building" then
      --Move one row down in a building inventory of some kind
      if players[pindex].building.sector <= #players[pindex].building.sectors then
         --Most building sectors, eg. chest rows
         if players[pindex].building.sectors[players[pindex].building.sector].inventory == nil or #players[pindex].building.sectors[players[pindex].building.sector].inventory < 1 then
            printout("blank sector", pindex)
            return
         end
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         local row_length = players[pindex].preferences.building_inventory_row_length
         if #players[pindex].building.sectors[players[pindex].building.sector].inventory > row_length then
            --Move one row down
            players[pindex].building.index = players[pindex].building.index + row_length
            if players[pindex].building.index > #players[pindex].building.sectors[players[pindex].building.sector].inventory then
               --Wrap around to the building inventory first row
               game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
               players[pindex].building.index = players[pindex].building.index % row_length
               --If the row is shorter than usual, get to its end
               if players[pindex].building.index < 1 then
                  players[pindex].building.index = row_length
               end
            end
         else
            --Inventory size < row length: Wrap over to the same slot
            game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
         end
         read_building_slot(pindex,false)
      elseif players[pindex].building.recipe_list == nil then
         --Move one row down in player inventory
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].inventory.index = players[pindex].inventory.index +10
         if players[pindex].inventory.index > players[pindex].inventory.max then
            players[pindex].inventory.index = players[pindex].inventory.index%10
            if players[pindex].inventory.index == 0 then
               players[pindex].inventory.index = 10
            end

         end
         read_inventory_slot(pindex)
      else
         if players[pindex].building.sector == #players[pindex].building.sectors + 1 then
            --Last building sector. Case = ??? **
            if players[pindex].building.recipe_selection then
               game.get_player(pindex).play_sound{path = "Inventory-Move"}
               players[pindex].building.index = 1
               players[pindex].building.category = players[pindex].building.category + 1
               if players[pindex].building.category > #players[pindex].building.recipe_list then
                  players[pindex].building.category = 1
               end
            end
            read_building_recipe(pindex)
         else
            --Case = ???
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].inventory.index = players[pindex].inventory.index +10
            if players[pindex].inventory.index > players[pindex].inventory.max then
               players[pindex].inventory.index = players[pindex].inventory.index%10
               if players[pindex].inventory.index == 0 then
                  players[pindex].inventory.index = 10
               end
            end
            read_inventory_slot(pindex)
            end
         end
   elseif players[pindex].menu == "technology" then
      if players[pindex].technology.category < 3 then
         players[pindex].technology.category = players[pindex].technology.category + 1
         players[pindex].technology.index = 1
      end
      if players[pindex].technology.category == 1 then
         printout("Researchable ttechnologies", pindex)
      elseif players[pindex].technology.category == 2 then
         printout("Locked technologies", pindex)
      elseif players[pindex].technology.category == 3 then
         printout("Past Research", pindex)
      end

   elseif players[pindex].menu == "belt" then
      if players[pindex].belt.sector == 1 then
         if (players[pindex].belt.side == 1 and players[pindex].belt.line1.valid and players[pindex].belt.index < 4) or (players[pindex].belt.side == 2 and players[pindex].belt.line2.valid and players[pindex].belt.index < 4) then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = players[pindex].belt.index + 1
         end
      elseif players[pindex].belt.sector == 2 then
         local max = 0
         if players[pindex].belt.side == 1 then
            max = #players[pindex].belt.network.combined.left
         elseif players[pindex].belt.side == 2 then
            max = #players[pindex].belt.network.combined.right
         end
         if players[pindex].belt.index < max then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = math.min(players[pindex].belt.index + 1, max)
         end
      elseif players[pindex].belt.sector == 3 then
         local max = 0
         if players[pindex].belt.side == 1 then
            max = #players[pindex].belt.network.downstream.left
         elseif players[pindex].belt.side == 2 then
            max = #players[pindex].belt.network.downstream.right
         end
         if players[pindex].belt.index < max then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = math.min(players[pindex].belt.index + 1, max)
         end
      elseif players[pindex].belt.sector == 4 then
         local max = 0
         if players[pindex].belt.side == 1 then
            max = #players[pindex].belt.network.upstream.left
         elseif players[pindex].belt.side == 2 then
            max = #players[pindex].belt.network.upstream.right
         end
         if players[pindex].belt.index < max then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].belt.index = math.min(players[pindex].belt.index + 1, max)
         end

      end
      read_belt_slot(pindex)
   elseif players[pindex].menu == "warnings" then
      local warnings = {}
      if players[pindex].warnings.sector == 1 then
         warnings = players[pindex].warnings.short.warnings
      elseif players[pindex].warnings.sector == 2 then
         warnings = players[pindex].warnings.medium.warnings
      elseif players[pindex].warnings.sector == 3 then
         warnings= players[pindex].warnings.long.warnings
      end
      if players[pindex].warnings.category < #warnings then
         players[pindex].warnings.category = players[pindex].warnings.category + 1
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].warnings.index = 1
      end
      read_warnings_slot(pindex)
   elseif players[pindex].menu == "pump" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      players[pindex].pump.index = math.min(#players[pindex].pump.positions, players[pindex].pump.index + 1)
      local dir = ""
      if players[pindex].pump.positions[players[pindex].pump.index].direction == 0 then
         dir = " North"
      elseif players[pindex].pump.positions[players[pindex].pump.index].direction == 4 then
         dir = " South"
      elseif players[pindex].pump.positions[players[pindex].pump.index].direction == 2 then
         dir = " East"
      elseif players[pindex].pump.positions[players[pindex].pump.index].direction == 6 then
         dir = " West"
      end

      printout("Option " .. players[pindex].pump.index .. ": " .. math.floor(distance(game.get_player(pindex).position, players[pindex].pump.positions[players[pindex].pump.index].position)) .. " meters " .. direction(game.get_player(pindex).position, players[pindex].pump.positions[players[pindex].pump.index].position) .. " Facing " .. dir, pindex)
   elseif players[pindex].menu == "travel" then
      if players[pindex].travel.index.y < #global.players[pindex].travel then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].travel.index.y = players[pindex].travel.index.y + 1
      else
         players[pindex].travel.index.y = #global.players[pindex].travel
      end
      players[pindex].travel.index.x = 1
      read_travel_slot(pindex)
   elseif players[pindex].menu == "structure-travel" then
      move_cursor_structure(pindex, 4)
   elseif players[pindex].menu == "rail_builder" then
      rail_builder_down(pindex)
   elseif players[pindex].menu == "train_stop_menu" then
      train_stop_menu_down(pindex)
   elseif players[pindex].menu == "roboport_menu" then
      roboport_menu_down(pindex)
   end
end

function menu_cursor_left(pindex)
   if players[pindex].item_selection then
         players[pindex].item_selector.index = math.max(1, players[pindex].item_selector.index - 1)
         read_item_selector_slot(pindex)

   elseif players[pindex].menu == "inventory" then
      players[pindex].inventory.index = players[pindex].inventory.index -1    
      if players[pindex].inventory.index%10 == 0 then
         if players[pindex].preferences.inventory_wraps_around == true then  
            --Wrap around setting: Move and play move sound and read slot
            players[pindex].inventory.index = players[pindex].inventory.index + 10
            game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
            read_inventory_slot(pindex)
         else 
            --Border setting: Undo change and play "wall" sound
            players[pindex].inventory.index = players[pindex].inventory.index +1
            game.get_player(pindex).play_sound{path = "player-mine"}
            printout("Border.", pindex)
         end
      else
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         read_inventory_slot(pindex)
      end

   elseif players[pindex].menu == "crafting" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      players[pindex].crafting.index = players[pindex].crafting.index -1
      if players[pindex].crafting.index < 1 then
         players[pindex].crafting.index = #players[pindex].crafting.lua_recipes[players[pindex].crafting.category]
      end
      read_crafting_slot(pindex)

   elseif players[pindex].menu == "crafting_queue" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      load_crafting_queue(pindex)
      if players[pindex].crafting_queue.index < 2 then
         players[pindex].crafting_queue.index = players[pindex].crafting_queue.max
      else
         players[pindex].crafting_queue.index = players[pindex].crafting_queue.index - 1
      end
      read_crafting_queue(pindex)
   elseif players[pindex].menu == "building" then
      --Move along a row in a building inventory
      if players[pindex].building.sector <= #players[pindex].building.sectors then
         --Most building sectors, e.g. chest rows
         if players[pindex].building.sectors[players[pindex].building.sector].inventory == nil or #players[pindex].building.sectors[players[pindex].building.sector].inventory < 1 then
            printout("blank sector", pindex)
            return
         end
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         local row_length = players[pindex].preferences.building_inventory_row_length
         if #players[pindex].building.sectors[players[pindex].building.sector].inventory > row_length then
            players[pindex].building.index = players[pindex].building.index - 1
            if players[pindex].building.index % row_length < 1 then
               --Wrap around to the end of this row
               game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
               players[pindex].building.index = players[pindex].building.index + row_length
               if players[pindex].building.index > #players[pindex].building.sectors[players[pindex].building.sector].inventory then
                  --If this final row is short, just jump to the end of the inventory
                  players[pindex].building.index = #players[pindex].building.sectors[players[pindex].building.sector].inventory
               end
            end
         else
            players[pindex].building.index = players[pindex].building.index - 1
            if players[pindex].building.index < 1 then
               --Wrap around to the end of this single-row inventory
               game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
               players[pindex].building.index = #players[pindex].building.sectors[players[pindex].building.sector].inventory
            end
         end
         read_building_slot(pindex,false)
      elseif players[pindex].building.recipe_list == nil then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].inventory.index = players[pindex].inventory.index -1
         if players[pindex].inventory.index%10 < 1 then
            players[pindex].inventory.index = players[pindex].inventory.index + 10
         end
         read_inventory_slot(pindex)
      else
         if players[pindex].building.sector == #players[pindex].building.sectors + 1 then
            --Recipe selection
            if players[pindex].building.recipe_selection then
               game.get_player(pindex).play_sound{path = "Inventory-Move"}
               players[pindex].building.index = players[pindex].building.index - 1
               if players[pindex].building.index < 1 then
                  players[pindex].building.index = #players[pindex].building.recipe_list[players[pindex].building.category]
               end
            end
            read_building_recipe(pindex)
         else
            --Case ???
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].inventory.index = players[pindex].inventory.index -1
            if players[pindex].inventory.index%10 < 1 then
               players[pindex].inventory.index = players[pindex].inventory.index + 10
            end
            read_inventory_slot(pindex)
            end
         end

   elseif players[pindex].menu == "technology" then
      if players[pindex].technology.index > 1 then
         players[pindex].technology.index = players[pindex].technology.index - 1
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
      end
      read_technology_slot(pindex)
   elseif players[pindex].menu == "belt" then
      if players[pindex].belt.side == 2 then
         players[pindex].belt.side = 1
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
            if not pcall(function()
            read_belt_slot(pindex)
         end) then
            printout("Blank", pindex)
         end
      end
   elseif players[pindex].menu == "warnings" then
      if players[pindex].warnings.index > 1 then
         players[pindex].warnings.index = players[pindex].warnings.index - 1
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
      end
      read_warnings_slot(pindex)
   elseif players[pindex].menu == "travel" then
      if players[pindex].travel.index.x > 1 then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].travel.index.x = players[pindex].travel.index.x - 1
      end
      if players[pindex].travel.index.x == 1 then
         printout("Travel", pindex)
      elseif players[pindex].travel.index.x == 2 then
         printout("Rename", pindex)
      elseif players[pindex].travel.index.x == 3 then
         printout("Delete", pindex)
      elseif players[pindex].travel.index.x == 4 then
         printout("Create New", pindex)
      end
   elseif players[pindex].menu == "structure-travel" then
      move_cursor_structure(pindex, 6)

   end
end

function menu_cursor_right(pindex)
   if players[pindex].item_selection then
         players[pindex].item_selector.index = math.min(#players[pindex].item_cache, players[pindex].item_selector.index + 1)
         read_item_selector_slot(pindex)

   elseif players[pindex].menu == "inventory" then
      players[pindex].inventory.index = players[pindex].inventory.index +1
      if players[pindex].inventory.index%10 == 1 then
         if players[pindex].preferences.inventory_wraps_around == true then  
            --Wrap around setting: Move and play move sound and read slot
            players[pindex].inventory.index = players[pindex].inventory.index - 10
            game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
            read_inventory_slot(pindex)
         else 
            --Border setting: Undo change and play "wall" sound
            players[pindex].inventory.index = players[pindex].inventory.index -1
            game.get_player(pindex).play_sound{path = "player-mine"}
            printout("Border.", pindex)
         end
      else
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         read_inventory_slot(pindex)
      end

   elseif players[pindex].menu == "crafting" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      players[pindex].crafting.index = players[pindex].crafting.index +1
      if players[pindex].crafting.index > #players[pindex].crafting.lua_recipes[players[pindex].crafting.category] then
         players[pindex].crafting.index = 1
      end
      read_crafting_slot(pindex)

   elseif players[pindex].menu == "crafting_queue" then
      game.get_player(pindex).play_sound{path = "Inventory-Move"}
      load_crafting_queue(pindex)
      if players[pindex].crafting_queue.index >= players[pindex].crafting_queue.max then
         players[pindex].crafting_queue.index = 1
      else
         players[pindex].crafting_queue.index = players[pindex].crafting_queue.index + 1
      end
      read_crafting_queue(pindex)
   elseif players[pindex].menu == "building" then
      --Move along a row in a building inventory
      if players[pindex].building.sector <= #players[pindex].building.sectors then
         --Most building sectors, e.g. chest inventories
         if players[pindex].building.sectors[players[pindex].building.sector].inventory == nil or #players[pindex].building.sectors[players[pindex].building.sector].inventory < 1 then
            printout("blank sector", pindex)
            return
         end
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         local row_length = players[pindex].preferences.building_inventory_row_length
         if #players[pindex].building.sectors[players[pindex].building.sector].inventory > row_length then
            players[pindex].building.index = players[pindex].building.index + 1
            if players[pindex].building.index % row_length == 1 then
               --Wrap back around to the start of this row
               game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
               players[pindex].building.index = players[pindex].building.index - row_length
            end
         else
            players[pindex].building.index = players[pindex].building.index + 1
            if players[pindex].building.index > #players[pindex].building.sectors[players[pindex].building.sector].inventory then
               --Wrap around to the start of the single-row inventory
               game.get_player(pindex).play_sound{path = "inventory-wrap-around"}
               players[pindex].building.index = 1
            end
         end
         read_building_slot(pindex,false)
      elseif players[pindex].building.recipe_list == nil then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].inventory.index = players[pindex].inventory.index +1
         if players[pindex].inventory.index%10 == 1 then
            players[pindex].inventory.index = players[pindex].inventory.index - 10
         end
         read_inventory_slot(pindex)
      else
         if players[pindex].building.sector == #players[pindex].building.sectors + 1 then
            --Recipe selection
            if players[pindex].building.recipe_selection then
               game.get_player(pindex).play_sound{path = "Inventory-Move"}

               players[pindex].building.index = players[pindex].building.index + 1
               if players[pindex].building.index > #players[pindex].building.recipe_list[players[pindex].building.category] then
                  players[pindex].building.index  = 1
               end
            end
            read_building_recipe(pindex)
         else
            --Case = ???
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            players[pindex].inventory.index = players[pindex].inventory.index +1
            if players[pindex].inventory.index%10 == 1 then
               players[pindex].inventory.index = players[pindex].inventory.index - 10
            end
            read_inventory_slot(pindex)
            end
         end
   elseif players[pindex].menu == "technology" then

      local techs = {}
      if players[pindex].technology.category == 1 then
         techs = players[pindex].technology.lua_researchable
      elseif players[pindex].technology.category == 2 then
         techs = players[pindex].technology.lua_locked
      elseif players[pindex].technology.category == 3 then
         techs = players[pindex].technology.lua_unlocked
      end
      if players[pindex].technology.index < #techs then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].technology.index = players[pindex].technology.index + 1
      end
      read_technology_slot(pindex)


   elseif players[pindex].menu == "belt" then
      if players[pindex].belt.side == 1 then
         players[pindex].belt.side = 2
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
            if not pcall(function()
            read_belt_slot(pindex)
         end) then
            printout("Blank", pindex)
         end
      end
   elseif players[pindex].menu == "warnings" then
      local warnings = {}
      if players[pindex].warnings.sector == 1 then
         warnings = players[pindex].warnings.short.warnings
      elseif players[pindex].warnings.sector == 2 then
         warnings = players[pindex].warnings.medium.warnings
      elseif players[pindex].warnings.sector == 3 then
         warnings= players[pindex].warnings.long.warnings
      end
      if warnings[players[pindex].warnings.category] ~= nil then
         local ents = warnings[players[pindex].warnings.category].ents
         if players[pindex].warnings.index < #ents then
            players[pindex].warnings.index = players[pindex].warnings.index + 1
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
         end
      end
      read_warnings_slot(pindex)
   elseif players[pindex].menu == "travel" then
      if players[pindex].travel.index.x < 4 then
         game.get_player(pindex).play_sound{path = "Inventory-Move"}
         players[pindex].travel.index.x = players[pindex].travel.index.x + 1
      end
      if players[pindex].travel.index.x == 1 then
         printout("Travel", pindex)
      elseif players[pindex].travel.index.x == 2 then
         printout("Rename", pindex)
      elseif players[pindex].travel.index.x == 3 then
         printout("Delete", pindex)
      elseif players[pindex].travel.index.x == 4 then
         printout("Create New", pindex)
      end
   elseif players[pindex].menu == "structure-travel" then
      move_cursor_structure(pindex, 2)

   end
end

function schedule(ticks_in_the_future,func_to_call, data_to_pass)
   if type(_G[func_to_call]) ~= "function" then
      Crash()
   end
   if ticks_in_the_future <=0 then
      _G[func_to_call](data_to_pass)
      return
   end
   local tick = game.tick + ticks_in_the_future
   local schedule = global.scheduled_events
   schedule[tick] = schedule[tick] or {}
   table.insert(schedule[tick], {func_to_call,data_to_pass})
end

function on_player_join(pindex)
   players = players or global.players
   schedule(3, "fix_zoom", pindex)
   local playerList={}
   for _ , p in pairs(game.connected_players) do
      playerList["_" .. p.index]=p.name
   end
   print("playerList " .. game.table_to_json(playerList))
   if game.players[pindex].name == "Crimso" then
      local player = game.get_player(pindex).cutscene_character or game.get_player(pindex).character
player.force.research_all_technologies()

--game.write_file('map.txt', game.table_to_json(game.parse_map_exchange_string(">>>eNpjZGBksGUAgwZ7EOZgSc5PzIHxgNiBKzm/oCC1SDe/KBVZmDO5qDQlVTc/E1Vxal5qbqVuUmIxsmJ7jsyi/Dx0E1iLS/LzUEVKilJTi5E1cpcWJeZlluai62VgnPIl9HFDixwDCP+vZ1D4/x+EgawHQL+AMANjA0glIyNQDAZYk3My09IYGBQcGRgKnFev0rJjZGSsFlnn/rBqij0jRI2eA5TxASpyIAkm4glj+DnglFKBMUyQzDEGg89IDIilJUAroKo4HBAMiGQLSJKREeZ2xl91WXtKJlfYM3qs3zPr0/UqO6A0O0iCCU7MmgkCO2FeYYCZ+cAeKnXTnvHsGRB4Y8/ICtIhAiIcLIDEAW9mBkYBPiBrQQ+QUJBhgDnNDmaMiANjGhh8g/nkMYxx2R7dH8CAsAEZLgciToAIsIVwl0F95tDvwOggD5OVRCgB6jdiQHZDCsKHJ2HWHkayH80hmBGB7A80ERUHLNHABbIwBU68YIa7BhieF9hhPIf5DozMIAZI1RegGIQHkoEZBaEFHMDBzcyAAMC0cepk2C4A0ySfhQ==<<<")))
   player.insert{name="pipe", count=100}
--   printout("Character loaded." .. #game.surfaces,  player.index)
--   player.insert{name="accumulator", count=10}
--   player.insert{name="beacon", count=10}
--   player.insert{name="boiler", count=10}
--   player.insert{name="centrifuge", count=10}
   player.insert{name="chemical-plant", count=10}
   player.insert{name="electric-mining-drill", count=10}
--   player.insert{name="heat-exchanger", count=10}
--   player.insert{name="nuclear-reactor", count=10}
   player.insert{name="offshore-pump", count=10}
   player.insert{name="oil-refinery", count=10}
--   player.insert{name="pumpjack", count=10}
--   player.insert{name="rocket-silo", count=1}
   player.insert{name="steam-engine", count=10}
   player.insert{name="wooden-chest", count=10}
   player.insert{name="assembling-machine-1", count=10}
--   player.insert{name="gun-turret", count=10}
   player.insert{name="transport-belt", count=100}
   player.insert{name="coal", count=100}
   player.insert{name="filter-inserter", count=10}
--   player.insert{name="fast-transport-belt", count=100}
--   player.insert{name="express-transport-belt", count=100}
   player.insert{name="small-electric-pole", count=100}
--   player.insert{name="big-electric-pole", count=100}
--   player.insert{name="substation", count=100}
--   player.insert{name="solar-panel", count=100}
--   player.insert{name="pipe-to-ground", count=100}
--   player.insert{name="underground-belt", count=100}
   for i = 0, 10 do
      for j = 0, 10 do
         player.surface.create_entity{name = "iron-ore", position = {i + .5, j + .5}}
      end
   end
--   player.force.research_all_technologies()
   end
   
   --Starting inventory boost
   local player = game.get_player(pindex).cutscene_character or game.get_player(pindex).character
   player.insert{name = "rocket-fuel", count = 20}
end

script.on_event(defines.events.on_player_joined_game,function(event)
   if game.is_multiplayer() then
      on_player_join(event.player_index)
   end
end)


function on_initial_joining_tick(event)
   if not game.is_multiplayer() then
      on_player_join(game.connected_players[1].index)
   end
   on_tick(event)
   script.on_event(defines.events.on_tick,on_tick)
end

function on_tick(event)
   if global.scheduled_events[event.tick] then
      for _, to_call in pairs(global.scheduled_events[event.tick]) do
         _G[to_call[1]](to_call[2])
      end
      global.scheduled_events[event.tick] = nil
   end
   move_characters(event)

   --The elseifs can schedule up to 16 events.
   if event.tick % 15 == 0 then
      for pindex, player in pairs(players) do
         check_and_play_bump_alert_sound(pindex,event.tick)
         check_and_play_stuck_alert_sound(pindex,event.tick)
      end
   elseif event.tick % 15 == 1 then
      --Check and play train track warning sounds at appropriate frequencies
      check_and_play_train_track_alert_sounds(3)
      check_and_play_enemy_alert_sound(3)
      if event.tick % 30 == 1 then
         check_and_play_train_track_alert_sounds(2)
         check_and_play_enemy_alert_sound(2)
         if event.tick % 60 == 1 then
            check_and_play_train_track_alert_sounds(1)
            check_and_play_enemy_alert_sound(1)
         end
      end
   elseif event.tick % 30 == 6 then
      --Check and play train horns
      for pindex, player in pairs(players) do
         check_and_honk_at_trains_in_same_block(event.tick,pindex)
         check_and_honk_at_closed_signal(event.tick,pindex)
      end
   elseif event.tick % 30 == 7 then
      --Update menu visuals
      update_menu_visuals()
   elseif event.tick % 60 == 11 then
      for pindex, player in pairs(players) do
         --If within 50 tiles of an enemy, try to aim at enemies and play sound to notify of enemies within shooting range
         local p = game.get_player(pindex)
         local enemy = p.surface.find_nearest_enemy{position = p.position, max_distance = 50, force = p.force}
         if enemy ~= nil and enemy.valid then
            aim_gun_at_nearest_enemy(pindex,enemy)
         end
      end
   elseif event.tick % 300 == 14 then
      for pindex, player in pairs(players) do
         --Fix running speed bug (toggle walk aldo fixes it)
         fix_walk(pindex)
      end
   end
end

--For each player, checks the open menu and appropriately calls to update the overhead sprite and GUI sprite
function update_menu_visuals()
   for pindex, player in pairs(players) do
      if player.in_menu then
         if player.menu == "technology" then
            update_overhead_sprite("item.lab",2,1.25,pindex)
            update_custom_GUI_sprite("item.lab", 3, pindex)
         elseif player.menu == "inventory" then
            update_overhead_sprite("item.wooden-chest",2,1.25,pindex)
            update_custom_GUI_sprite("item.wooden-chest", 3, pindex)
            if players[pindex].vanilla_mode then
               update_custom_GUI_sprite(nil,1,pindex)
            end
         elseif player.menu == "crafting" then
            update_overhead_sprite("item.repair-pack",2,1.25,pindex)
            update_custom_GUI_sprite("item.repair-pack", 3, pindex)
         elseif player.menu == "crafting_queue" then
            update_overhead_sprite("item.repair-pack",2,1.25,pindex)
            update_custom_GUI_sprite("item.repair-pack", 3, pindex)
         elseif player.menu == "travel" then
            update_overhead_sprite("utility.downloading_white",4,1.25,pindex)
            update_custom_GUI_sprite("utility.downloading_white", 3, pindex)
         elseif player.menu == "warnings" then
            update_overhead_sprite("utility.warning_white",4,1.25,pindex)
            update_custom_GUI_sprite("utility.warning_white", 3, pindex)
         elseif player.menu == "rail_builder" then
            update_overhead_sprite("item.rail",2,1.25,pindex)
            update_custom_GUI_sprite("item.rail", 3, pindex)
         elseif player.menu == "train_menu" then
            update_overhead_sprite("item.locomotive",2,1.25,pindex)
            update_custom_GUI_sprite("item.locomotive", 3, pindex)
         elseif player.menu == "train_stop_menu" then
            update_overhead_sprite("item.train-stop",2,1.25,pindex)
            update_custom_GUI_sprite("item.train-stop", 3, pindex)
         elseif player.menu == "roboport_menu" then
            update_overhead_sprite("item.roboport",2,1.25,pindex)
            update_custom_GUI_sprite("item.roboport", 3, pindex)
         elseif player.menu == "belt" then
            update_overhead_sprite("item.transport-belt",2,1.25,pindex)
            update_custom_GUI_sprite(nil,1,pindex)
         elseif player.menu == "building" then
            if game.get_player(pindex).opened == nil then
               --Open building menu with no GUI
               update_overhead_sprite("utility.search_white",2,1.25,pindex)
               update_custom_GUI_sprite("utility.search_white", 3, pindex)
            else
               --A building with a GUI is open
               update_overhead_sprite("utility.search_white",2,1.25,pindex)
               update_custom_GUI_sprite(nil,1,pindex)
            end
         elseif player.menu == "structure-travel" then
            update_overhead_sprite("utility.expand_dots_white",2,1.25,pindex)
            update_custom_GUI_sprite("utility.expand_dots_white",3,pindex)
         else
            --Other menu type ...
            update_overhead_sprite("utility.select_icon_white",1,1,pindex)
            update_custom_GUI_sprite("utility.select_icon_white",1,pindex)
         end
      else
         if game.get_player(pindex).opened ~= nil then
            --Not in menu, but open GUI
            update_overhead_sprite("utility.white_square",2,1.25,pindex)
            update_custom_GUI_sprite(nil,1,pindex)
         else
            --Not in menu, no open GUI
            update_overhead_sprite(nil,1,1,pindex)
            update_custom_GUI_sprite(nil,1,pindex)
         end
      end
   end
end


script.on_event(defines.events.on_tick,on_initial_joining_tick)
function move_characters(event)
   for pindex, player in pairs(players) do
      if player.walk ~= 2 or player.cursor or player.in_menu then
         local walk = false
         while #player.move_queue > 0 do
            local next_move = player.move_queue[1]
            player.player.walking_state = {walking = true, direction = next_move.direction}
            if next_move.direction == defines.direction.north then
               walk = player.player.position.y > next_move.dest.y
            elseif next_move.direction == defines.direction.south then
               walk = player.player.position.y < next_move.dest.y
            elseif next_move.direction == defines.direction.east then
               walk = player.player.position.x < next_move.dest.x
            elseif next_move.direction == defines.direction.west then
               walk = player.player.position.x > next_move.dest.x
            end
            
            if walk then
               game.get_player(pindex).game_view_settings.update_entity_selection = true
               break
            else
               table.remove(player.move_queue,1)
            end
         end
         if not walk then
            player.player.walking_state = {walking = false}
         end
      elseif player.walk == 2 and not player.cursor and not player.in_menu then
         game.get_player(pindex).game_view_settings.update_entity_selection = true
      end
   end
end



function add_position(p1,p2)
   return { x = p1.x + p2.x, y = p1.y + p2.y}
end

function sub_position(p1,p2)
   return { x = p1.x - p2.x, y = p1.y - p2.y}
end

function mult_position(p,m)
   return { x = p.x * m, y = p.y * m }
end

function offset_position(oldpos,direction,distance)
   if direction == defines.direction.north then
      return { x = oldpos.x, y = oldpos.y - distance}
   elseif direction == defines.direction.south then
      return { x = oldpos.x, y = oldpos.y + distance}
   elseif direction == defines.direction.east then
      return { x = oldpos.x + distance, y = oldpos.y}
   elseif direction == defines.direction.west then
      return { x = oldpos.x - distance, y = oldpos.y}
   elseif direction == defines.direction.northwest then
      return { x = oldpos.x - distance, y = oldpos.y - distance}
   elseif direction == defines.direction.northeast then
      return { x = oldpos.x + distance, y = oldpos.y - distance}
   elseif direction == defines.direction.southwest then
      return { x = oldpos.x - distance, y = oldpos.y + distance}
   elseif direction == defines.direction.southeast then
      return { x = oldpos.x + distance, y = oldpos.y + distance}
   end
end

--Move player character (and adapt the cursor to smooth walking)
function move(direction,pindex)
   if game.get_player(pindex).driving then
      return
   end
   local first_player = game.get_player(pindex)
   local pos = players[pindex].position
   local new_pos = offset_position(pos,direction,1)
   if players[pindex].player_direction == direction then
      --move character:
      if players[pindex].walk == 2 then
         return
      end
      can_port = first_player.surface.can_place_entity{name = "character", position = new_pos}
      if can_port then
         if players[pindex].walk == 1 then
            table.insert(players[pindex].move_queue,{direction=direction,dest=new_pos})
         else
            teleported = first_player.teleport(new_pos)
            if not teleported then
               printout("Teleport Failed", pindex)
            end
         end
         players[pindex].position = new_pos
         players[pindex].cursor_pos = offset_position(players[pindex].position, direction,1)
         cursor_highlight(pindex, nil, nil)
         sync_build_arrow(pindex)
         if players[pindex].tile.previous ~= nil
            and players[pindex].tile.previous.valid
            and players[pindex].tile.previous.type == "transport-belt"
         then
            game.get_player(pindex).play_sound{path = "utility/metal_walking_sound"}
         else
            local tile = game.get_player(pindex).surface	.get_tile(new_pos.x, new_pos.y)
            local sound_path = "tile-walking/" .. tile.name
            if game.is_valid_sound_path(sound_path) then
               game.get_player(pindex).play_sound{path = "tile-walking/" .. tile.name}
            end
         end
         if not game.get_player(pindex).driving then
            read_tile(pindex)
         end
         target(pindex)
         
         if players[pindex].build_lock then
            build_item_in_hand(pindex, -2)
         end
      else
         printout("Tile Occupied", pindex)
         target(pindex)
      end
   else
      --turn character:
      if players[pindex].walk == 0 then
         game.get_player(pindex).play_sound{path = "player-turn"}
      elseif players[pindex].walk == 1 then
         table.insert(players[pindex].move_queue,{direction=direction,dest=pos})
      end
      players[pindex].player_direction = direction
      players[pindex].cursor_pos = new_pos
      cursor_highlight(pindex, nil, nil)
      sync_build_arrow(pindex)
      target(pindex)
      if game.get_player(pindex).driving then
         target(pindex)
      elseif players[pindex].walk ~= 2 then
         read_tile(pindex)
      elseif players[pindex].walk == 2 then
         refresh_player_tile(pindex)
         local ent = get_selected_ent(pindex)
         if not players[pindex].vanilla_mode and ((ent ~= nil and ent.valid) or not game.get_player(pindex).surface.can_place_entity{name = "character", position = players[pindex].cursor_pos}) then
            target(pindex)
            read_tile(pindex)
         end
      end
      
      --Rotate belts in hand for build lock Mode
      local stack = game.get_player(pindex).cursor_stack
      if players[pindex].build_lock and stack.valid_for_read and stack.valid and stack.prototype.place_result ~= nil and stack.prototype.place_result.type == "transport-belt" then 
         players[pindex].building_direction = math.floor(players[pindex].player_direction / dirs.east)
      end
   end
   
   --Unless the cut-paste tool is in hand, restore the reading of flying text 
   local stack = game.get_player(pindex).cursor_stack
   if not (stack and stack.valid_for_read and stack.name == "cut-paste-tool") then
      players[pindex].allow_reading_flying_text = true
   end
end

function move_key(direction,event, force_single_tile)
   local pindex = event.player_index
   if not check_for_player(pindex) or players[pindex].menu == "prompt" then
      return 
   end
   local single_only = force_single_tile or false
   
   --Save the key press event
   local pex = players[event.player_index]
   pex.bump.last_dir_key_2nd = pex.bump.last_dir_key_1st
   pex.bump.last_dir_key_1st = direction
   pex.bump.last_dir_key_tick = event.tick
   
   if players[pindex].in_menu and players[pindex].menu ~= "prompt" then
      -- Menus: move menu cursor
      menu_cursor_move(direction,pindex)
   elseif players[pindex].cursor then
      -- Cursor mode: Move cursor on map
      local diff = players[pindex].cursor_size * 2 + 1
      if single_only then
         diff = 1
      end
      players[pindex].cursor_pos = offset_position(players[pindex].cursor_pos, direction, diff)
      if not players[pindex].vanilla_mode then
         players[pindex].cursor_pos = center_of_tile(players[pindex].cursor_pos)
         target(pindex)
      end
      sync_build_arrow(pindex)
      if players[pindex].cursor_size == 0 then
         -- Cursor size 0 ("1 by 1"): read tile
         if not game.get_player(pindex).driving then
            read_tile(pindex)
         end
         target(pindex)
         players[pindex].player_direction = direction
         if players[pindex].build_lock then
            build_item_in_hand(pindex, -1)            
         end
      elseif not game.get_player(pindex).driving then
         -- Larger cursor sizes: scan area
         local scan_left_top = {math.floor(players[pindex].cursor_pos.x)-players[pindex].cursor_size,math.floor(players[pindex].cursor_pos.y)-players[pindex].cursor_size}
         local scan_right_bottom = {math.floor(players[pindex].cursor_pos.x)+players[pindex].cursor_size+1,math.floor(players[pindex].cursor_pos.y)+players[pindex].cursor_size+1}
         players[pindex].nearby.index = 1
         players[pindex].nearby.ents = scan_area(math.floor(players[pindex].cursor_pos.x)-players[pindex].cursor_size, math.floor(players[pindex].cursor_pos.y)-players[pindex].cursor_size, players[pindex].cursor_size * 2 + 1, players[pindex].cursor_size * 2 + 1, pindex)
         populate_categories(pindex)
         local scan_summary = get_scan_summary(scan_left_top, scan_right_bottom, pindex)
         draw_area_as_cursor(scan_left_top,scan_right_bottom,pindex)
         printout(scan_summary,pindex)
      end
   else
      -- General case: Move character
      move(direction,pindex)
   end
end

--Called when a player enters or exits a vehicle
script.on_event(defines.events.on_player_driving_changed_state, function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   reset_bump_stats(pindex)
   game.get_player(pindex).clear_cursor()
   if game.get_player(pindex).driving then
      players[pindex].last_vehicle = game.get_player(pindex).vehicle
      printout("Entered " .. game.get_player(pindex).vehicle.name ,pindex)
      if players[pindex].last_vehicle.train ~= nil and players[pindex].last_vehicle.train.schedule == nil then
         players[pindex].last_vehicle.train.manual_mode = true
      end
   elseif players[pindex].last_vehicle ~= nil then
      printout("Exited " .. players[pindex].last_vehicle.name ,pindex)
      if players[pindex].last_vehicle.train ~= nil and players[pindex].last_vehicle.train.schedule == nil then
         players[pindex].last_vehicle.train.manual_mode = true
      end
      teleport_to_closest(pindex, players[pindex].last_vehicle.position, true, true)
      if players[pindex].menu == "train_menu" then
         train_menu_close(pindex, false)
      end
   else
      printout("Driving state changed." ,pindex)
   end
end)

--Pause / resume the game 
script.on_event("pause-game-fa", function(event)
   if game.tick_paused == true then
      for pindex, player in pairs(players) do
         printout("Game paused", pindex)--does not call**
      end
   else
      for pindex, player in pairs(players) do
         printout("Game resumed", pindex)
      end
   end
end)

script.on_event("cursor-up", function(event)
   move_key(defines.direction.north,event)
end)

script.on_event("cursor-down", function(event)
   move_key(defines.direction.south,event)
end)

script.on_event("cursor-left", function(event)
   move_key(defines.direction.west,event)
end)
script.on_event("cursor-right", function(event)
   move_key(defines.direction.east,event)
end)


--Read coordinates of the cursor. Extra info as well such as entity part if an entity is selected, and heading and speed info for vehicles.
script.on_event("read-cursor-coords", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   read_coords(pindex)
end
)

--Get distance and direction of cursor from player.
script.on_event("read-cursor-distance-and-direction", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   --Read where the cursor is with respect to the player, e.g. "at 5 west"
   local dir_dist = dir_dist_locale(players[pindex].position, players[pindex].cursor_pos)
   local cursor_location_description = "at"
   local cursor_production = " "
   local cursor_description_of = " "
   local result={"access.thing-producing-listpos-dirdist",cursor_location_description}
   table.insert(result,cursor_production)--no production
   table.insert(result,cursor_description_of)--listpos
   table.insert(result,dir_dist)
   printout(result,pindex)
end)

--Returns the cursor to the player position.
script.on_event("return-cursor-to-player", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex) 
   if not (players[pindex].in_menu) then
      if players[pindex].cursor then 
         jump_to_player(pindex)
      end
   end
end)

--Default is CONTROL + J
script.on_event("release-cursor", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   game.get_player(pindex).game_view_settings.update_entity_selection = true
   printout("cursor released",pindex)
   cursor_highlight(pindex, nil, nil)
end)

script.on_event("teleport-to-cursor", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   teleport_to_cursor(pindex, false, false, false)
end)

script.on_event("teleport-to-cursor-forced", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   teleport_to_cursor(pindex, false, true, false)
end)

script.on_event("teleport-to-alert-forced", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local alert_pos = players[pindex].last_damage_alert_pos
   if alert_pos == nil then
      printout("No target",pindex)
      return
   end
   players[pindex].cursor_pos = alert_pos
   teleport_to_cursor(pindex, false, true, true)
   players[pindex].cursor_pos = game.get_player(pindex).position
   players[pindex].position = game.get_player(pindex).position
   players[pindex].last_damage_alert_pos = game.get_player(pindex).position
   cursor_highlight(pindex, nil, nil)
   sync_build_arrow(pindex)
   refresh_player_tile(pindex)
end)

script.on_event("toggle-cursor", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      players[pindex].move_queue = {}
      toggle_cursor(pindex)
   end
end)

--We have cursor sizes 1,3,5,11,21,101,251
script.on_event("cursor-size-increment", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      if players[pindex].cursor_size == 0 then
         players[pindex].cursor_size = 1
      elseif players[pindex].cursor_size == 1 then
         players[pindex].cursor_size = 2
      elseif players[pindex].cursor_size == 2 then
         players[pindex].cursor_size = 5
      elseif players[pindex].cursor_size == 5 then
         players[pindex].cursor_size = 10
      elseif players[pindex].cursor_size == 10 then
         players[pindex].cursor_size = 50
      elseif players[pindex].cursor_size == 50 then
         players[pindex].cursor_size = 125
      end
      
      local say_size = players[pindex].cursor_size * 2 + 1
      printout("Cursor size " .. say_size .. " by " .. say_size, pindex)
      local scan_left_top = {math.floor(players[pindex].cursor_pos.x)-players[pindex].cursor_size,math.floor(players[pindex].cursor_pos.y)-players[pindex].cursor_size}
      local scan_right_bottom = {math.floor(players[pindex].cursor_pos.x)+players[pindex].cursor_size+1,math.floor(players[pindex].cursor_pos.y)+players[pindex].cursor_size+1}
      draw_area_as_cursor(scan_left_top,scan_right_bottom,pindex)
   end
end)

--We have cursor sizes 1,3,5,11,21,101,251
script.on_event("cursor-size-decrement", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      if players[pindex].cursor_size == 1 then
         players[pindex].cursor_size = 0
      elseif players[pindex].cursor_size == 2 then
         players[pindex].cursor_size = 1
      elseif players[pindex].cursor_size == 5 then
         players[pindex].cursor_size = 2
      elseif players[pindex].cursor_size == 10 then
         players[pindex].cursor_size = 5
      elseif players[pindex].cursor_size == 50 then
         players[pindex].cursor_size = 10
      elseif players[pindex].cursor_size == 125 then
         players[pindex].cursor_size = 50
      end
      
      local say_size = players[pindex].cursor_size * 2 + 1
      printout("Cursor size " .. say_size .. " by " .. say_size, pindex)
      local scan_left_top = {math.floor(players[pindex].cursor_pos.x)-players[pindex].cursor_size,math.floor(players[pindex].cursor_pos.y)-players[pindex].cursor_size}
      local scan_right_bottom = {math.floor(players[pindex].cursor_pos.x)+players[pindex].cursor_size+1,math.floor(players[pindex].cursor_pos.y)+players[pindex].cursor_size+1}
      draw_area_as_cursor(scan_left_top,scan_right_bottom,pindex)
   end
end)

script.on_event("increase-inventory-bar-by-1", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "building" then 
      --Chest bar setting: Increase
	  local ent = get_selected_ent(pindex)
	  local result = increment_inventory_bar(ent, 1)
	  printout(result, pindex)
   end
end)

script.on_event("increase-inventory-bar-by-5", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "building" then 
      --Chest bar setting: Increase
	  local ent = get_selected_ent(pindex)
	  local result = increment_inventory_bar(ent, 1)
	  printout(result, pindex)
   end
end)

script.on_event("increase-inventory-bar-by-100", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "building" then 
      --Chest bar setting: Increase
	  local ent = get_selected_ent(pindex)
	  local result = increment_inventory_bar(ent, 100)
	  printout(result, pindex)
   end
end)

script.on_event("decrease-inventory-bar-by-1", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "building" then 
      --Chest bar setting: Decrease
	  local ent = get_selected_ent(pindex)
	  local result = increment_inventory_bar(ent, -1)
	  printout(result, pindex)
   end
end)

script.on_event("decrease-inventory-bar-by-5", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "building" then 
      --Chest bar setting: Decrease
	  local ent = get_selected_ent(pindex)
	  local result = increment_inventory_bar(ent, -5)
	  printout(result, pindex)
   end
end)

script.on_event("decrease-inventory-bar-by-100", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "building" then 
      --Chest bar setting: Decrease
	  local ent = get_selected_ent(pindex)
	  local result = increment_inventory_bar(ent, -100)
	  printout(result, pindex)
   end
end)

script.on_event("increase-train-wait-times-by-5", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then 
      change_instant_schedule_wait_time(5,pindex)
   elseif players[pindex].in_menu and players[pindex].menu == "train_stop_menu" then 
      nearby_train_schedule_change_wait_time(5,pindex)
   end
end)

script.on_event("increase-train-wait-times-by-60", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then 
      change_instant_schedule_wait_time(60,pindex)
   elseif players[pindex].in_menu and players[pindex].menu == "train_stop_menu" then 
      nearby_train_schedule_change_wait_time(60,pindex)
   end
end)

script.on_event("decrease-train-wait-times-by-5", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then 
      change_instant_schedule_wait_time(-5,pindex)
   elseif players[pindex].in_menu and players[pindex].menu == "train_stop_menu" then 
      nearby_train_schedule_change_wait_time(-5,pindex)
   end
end)

script.on_event("decrease-train-wait-times-by-60", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then 
      change_instant_schedule_wait_time(-60,pindex)
   elseif players[pindex].in_menu and players[pindex].menu == "train_stop_menu" then 
      nearby_train_schedule_change_wait_time(-60,pindex)
   end
end)

script.on_event("read-rail-structure-ahead", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex) 
   if game.get_player(pindex).driving and game.get_player(pindex).vehicle.train ~= nil then
      train_read_next_rail_entity_ahead(pindex,false)
   elseif ent ~= nil and ent.valid and (ent.name == "straight-rail" or ent.name == "curved-rail") then
      --Report what is along the rail
      rail_read_next_rail_entity_ahead(pindex, ent, true)
   end
end)

script.on_event("read-rail-structure-behind", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex) 
   if game.get_player(pindex).driving and game.get_player(pindex).vehicle.train ~= nil then
      train_read_next_rail_entity_ahead(pindex,true)
   elseif ent ~= nil and ent.valid and (ent.name == "straight-rail" or ent.name == "curved-rail") then
      --Report what is along the rail
      rail_read_next_rail_entity_ahead(pindex, ent, false)
   end
end)

script.on_event("rescan", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      rescan(pindex)
      printout("Scan Complete", pindex)
      run_scanner_effects(pindex)
   end
end)

script.on_event("scan-facing-direction", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      --Set the filter direction 
      local p = game.get_player(pindex)
      local dir = p.walking_state.direction
      rescan(pindex,dir)
      printout("Scanning " .. direction_lookup(dir), pindex)
      run_scanner_effects(pindex)
   end
end)

--Sound and visual effects for the scanner
function run_scanner_effects(pindex)
   --Scanner visual and sound effects
   game.get_player(pindex).play_sound{path = "scanner-pulse"}
   rendering.draw_circle{color = {1, 1, 1},radius = 1,width =  4,target = game.get_player(pindex).position, surface = game.get_player(pindex).surface, draw_on_ground = true, time_to_live = 60}
   rendering.draw_circle{color = {1, 1, 1},radius = 2,width =  8,target = game.get_player(pindex).position, surface = game.get_player(pindex).surface, draw_on_ground = true, time_to_live = 60}
end

script.on_event("a-scan-list-main-up-key", function(event)
   --laterdo: find a more elegant scan list solution here. It depends on hardcoded keybindings and alphabetically named event handling
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   players[pindex].last_pg_key_tick = event.tick
end)

script.on_event("a-scan-list-main-down-key", function(event)
   --laterdo: find a more elegant scan list solution here. It depends on hardcoded keybindings and alphabetically named event handling
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   players[pindex].last_pg_key_tick = event.tick
end)

script.on_event("scan-list-up", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not players[pindex].in_menu and not players[pindex].cursor then
      scan_up(pindex)
   end
   if players[pindex].cursor and players[pindex].last_pg_key_tick ~= nil and event.tick - players[pindex].last_pg_key_tick < 10 then
      scan_up(pindex)
   end
end)

script.on_event("scan-list-down", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not players[pindex].in_menu and not players[pindex].cursor then
      scan_down(pindex)
   end
   if players[pindex].cursor and players[pindex].last_pg_key_tick ~= nil and event.tick - players[pindex].last_pg_key_tick < 10 then
      scan_down(pindex)
   end
end)

script.on_event("scan-list-middle", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not players[pindex].in_menu then
      scan_middle(pindex)
   end
end)

script.on_event("jump-to-scan", function(event)--NOTE: This might be deprecated or redundant, since the cursor already goes to the scanned object now. laterdo remove?
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      if (players[pindex].nearby.category == 1 and next(players[pindex].nearby.ents) == nil) or 
         (players[pindex].nearby.category == 2 and next(players[pindex].nearby.resources) == nil) or 
         (players[pindex].nearby.category == 3 and next(players[pindex].nearby.containers) == nil) or 
         (players[pindex].nearby.category == 4 and next(players[pindex].nearby.buildings) == nil) or 
         (players[pindex].nearby.category == 5 and next(players[pindex].nearby.vehicles) == nil) or 
         (players[pindex].nearby.category == 6 and next(players[pindex].nearby.players) == nil) or 
         (players[pindex].nearby.category == 7 and next(players[pindex].nearby.enemies) == nil) or 
         (players[pindex].nearby.category == 8 and next(players[pindex].nearby.other) == nil) then
         printout("No entities found.  Try refreshing with end key.", pindex)
      else
         local ents = {}
         if players[pindex].nearby.category == 1 then
            ents = players[pindex].nearby.ents
         elseif players[pindex].nearby.category == 2 then
            ents = players[pindex].nearby.resources
         elseif players[pindex].nearby.category == 3 then
            ents = players[pindex].nearby.containers
         elseif players[pindex].nearby.category == 4 then
            ents = players[pindex].nearby.buildings
         elseif players[pindex].nearby.category == 5 then
            ents = players[pindex].nearby.vehicles
         elseif players[pindex].nearby.category == 6 then
            ents = players[pindex].nearby.players
         elseif players[pindex].nearby.category == 7 then
            ents = players[pindex].nearby.enemies
         elseif players[pindex].nearby.category == 8 then
            ents = players[pindex].nearby.other
         end
         local ent = nil
         if ents.aggregate == false then
            local i = 1
            while i <= #ents[players[pindex].nearby.index].ents do
               if ents[players[pindex].nearby.index].ents[i].valid then
                  i = i + 1
               else
                  table.remove(ents[players[pindex].nearby.index].ents, i)
                  if players[pindex].nearby.selection > i then
                     players[pindex].nearby.selection = players[pindex].nearby.selection - 1
                  end
               end
            end
            if #ents[players[pindex].nearby.index].ents == 0 then
               table.remove(ents,players[pindex].nearby.index)
               players[pindex].nearby.index = math.min(players[pindex].nearby.index, #ents)
               scan_index(pindex)
               return
            end

            table.sort(ents[players[pindex].nearby.index].ents, function(k1, k2) 
               local pos = players[pindex].position
               return distance(pos, k1.position) < distance(pos, k2.position)
            end)
            if players[pindex].nearby.selection > #ents[players[pindex].nearby.index].ents then
               players[pindex].selection = 1
            end

            ent = ents[players[pindex].nearby.index].ents[players[pindex].nearby.selection]
            if ent == nil then
               printout("Error: This object no longer exists. Try rescanning.", pindex)
               return
            end
            if not ent.valid then
               printout("Error: This object is no longer valid. Try rescanning.", pindex)
               return
            end
         else
            if players[pindex].nearby.selection > #ents[players[pindex].nearby.index].ents then
               players[pindex].selection = 1
            end
            local name = ents[players[pindex].nearby.index].name
            local entry = ents[players[pindex].nearby.index].ents[players[pindex].nearby.selection]
            if table_size(entry) == 0 then
               table.remove(ents[players[pindex].nearby.index].ents, players[pindex].nearby.selection)
               players[pindex].nearby.selection = players[pindex].nearby.selection - 1
               scan_index(pindex)
               return
            end
            if entry == nil then
               printout("Error: This scanned object no longer exists. Try rescanning.", pindex)
               return
            end
            if not entry.valid and not (name == "water" or name == "coal" or name == "stone" or name == "iron-ore" or name == "copper-ore" or name == "uranium-ore" or name == "crude-oil" or name == "forest") then--laterdo maybe this check needs to just be an aggregate check
               printout("Error: This scanned object is no longer valid. Try rescanning.", pindex)--laterdo possible crash when trying to teleport to an entry that was depleted...
               --game.get_player(pindex).print("invalid: " .. name)
               return
            end
            ent = {name = name, position = table.deepcopy(entry.position)}--**beta** (fixed)
         end
         if players[pindex].cursor then
            players[pindex].cursor_pos = center_of_tile(ent.position)
            cursor_highlight(pindex, ent, nil)
            sync_build_arrow(pindex)
            printout("Cursor has jumped to " .. ent.name .. " at " .. math.floor(players[pindex].cursor_pos.x) .. " " .. math.floor(players[pindex].cursor_pos.y), pindex)
         else
            teleport_to_closest(pindex, ent.position, false, false)
            players[pindex].cursor_pos = offset_position(players[pindex].position, players[pindex].player_direction, 1)
            cursor_highlight(pindex, nil, nil)--laterdo check for new cursor ent here, to update the highlight?
            sync_build_arrow(pindex)
         end
      end
   end
end)

script.on_event("scan-category-up", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      local new_category = players[pindex].nearby.category - 1
      while new_category > 0 and (
      (new_category == 1 and next(players[pindex].nearby.ents) == nil) or 
      (new_category == 2 and next(players[pindex].nearby.resources) == nil) or 
      (new_category == 3 and next(players[pindex].nearby.containers) == nil) or 
      (new_category == 4 and next(players[pindex].nearby.buildings) == nil) or 
      (new_category == 5 and next(players[pindex].nearby.vehicles) == nil) or 
      (new_category == 6 and next(players[pindex].nearby.players) == nil) or 
      (new_category == 7 and next(players[pindex].nearby.enemies) == nil) or 
      (new_category == 8 and next(players[pindex].nearby.other) == nil)) do
         new_category = new_category - 1
      end
      if new_category > 0 then
         players[pindex].nearby.index = 1
         players[pindex].nearby.category = new_category
      end
      if players[pindex].nearby.category == 1 then
         printout("All", pindex)
      elseif players[pindex].nearby.category == 2 then
         printout("Resources", pindex)
      elseif players[pindex].nearby.category == 3 then
         printout("Containers", pindex)
      elseif players[pindex].nearby.category == 4 then
         printout("Buildings", pindex)
      elseif players[pindex].nearby.category == 5 then
         printout("Vehicles", pindex)
      elseif players[pindex].nearby.category == 6 then
         printout("Players", pindex)
      elseif players[pindex].nearby.category == 7 then
         printout("Enemies", pindex)
      elseif players[pindex].nearby.category == 8 then
         printout("Other", pindex)
      end
   end
end)

script.on_event("scan-category-down", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      local new_category  = players[pindex].nearby.category + 1
      while new_category <= 8 and (
         (new_category == 1 and next(players[pindex].nearby.ents) == nil) or 
         (new_category == 2 and next(players[pindex].nearby.resources) == nil) or 
         (new_category == 3 and next(players[pindex].nearby.containers) == nil) or 
         (new_category == 4 and next(players[pindex].nearby.buildings) == nil) or 
         (new_category == 5 and next(players[pindex].nearby.vehicles) == nil) or 
         (new_category == 6 and next(players[pindex].nearby.players) == nil) or 
         (new_category == 7 and next(players[pindex].nearby.enemies) == nil) or 
         (new_category == 8 and next(players[pindex].nearby.other) == nil) ) do
         new_category = new_category + 1
      end
      if new_category <= 8 then
         players[pindex].nearby.category = new_category
         players[pindex].nearby.index = 1
      end
    
      if players[pindex].nearby.category == 1 then
         printout("All", pindex)
      elseif players[pindex].nearby.category == 2 then
         printout("Resources", pindex)
      elseif players[pindex].nearby.category == 3 then
         printout("Containers", pindex)
      elseif players[pindex].nearby.category == 4 then
         printout("Buildings", pindex)
      elseif players[pindex].nearby.category == 5 then
         printout("Vehicles", pindex)
      elseif players[pindex].nearby.category == 6 then
         printout("Players", pindex)
      elseif players[pindex].nearby.category == 7 then
         printout("Enemies", pindex)
      elseif players[pindex].nearby.category == 8 then
         printout("Other", pindex)
      end
   end
end)

--Default key was N
script.on_event("scan-mode-up", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      players[pindex].nearby.index = 1
      players[pindex].nearby.count = false
      printout("Sorting by distance from your position", pindex)
      scan_sort(pindex)
   end
end)

--Default key was SHIFT + N
script.on_event("scan-mode-down", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      players[pindex].nearby.index = 1
      players[pindex].nearby.count = true
      printout("Sorting by count", pindex)
      scan_sort(pindex)
   end
end)

--Move along different inmstances of the same item type
script.on_event("scan-selection-up", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      if players[pindex].nearby.selection > 1 then
         players[pindex].nearby.selection = players[pindex].nearby.selection - 1
      else
         game.get_player(pindex).play_sound{path = "player-mine"}
         players[pindex].nearby.selection = 1
      end
      scan_index(pindex)
   end
end)

--Move along different inmstances of the same item type
script.on_event("scan-selection-down", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      if (players[pindex].nearby.category == 1 and next(players[pindex].nearby.ents) == nil) or 
      (players[pindex].nearby.category == 2 and next(players[pindex].nearby.resources) == nil) or 
      (players[pindex].nearby.category == 3 and next(players[pindex].nearby.containers) == nil) or 
      (players[pindex].nearby.category == 4 and next(players[pindex].nearby.buildings) == nil) or 
      (players[pindex].nearby.category == 5 and next(players[pindex].nearby.vehicles) == nil) or 
      (players[pindex].nearby.category == 6 and next(players[pindex].nearby.players) == nil) or 
      (players[pindex].nearby.category == 7 and next(players[pindex].nearby.enemies) == nil) or 
      (players[pindex].nearby.category == 8 and next(players[pindex].nearby.other) == nil) then
         printout("No entities found.  Try refreshing with end key.", pindex)
      else
         local ents = {}
         if players[pindex].nearby.category == 1 then
            ents = players[pindex].nearby.ents
         elseif players[pindex].nearby.category == 2 then
            ents = players[pindex].nearby.resources
         elseif players[pindex].nearby.category == 3 then
            ents = players[pindex].nearby.containers
         elseif players[pindex].nearby.category == 4 then
            ents = players[pindex].nearby.buildings
         elseif players[pindex].nearby.category == 5 then
            ents = players[pindex].nearby.vehicles
         elseif players[pindex].nearby.category == 6 then
            ents = players[pindex].nearby.players
         elseif players[pindex].nearby.category == 7 then
            ents = players[pindex].nearby.enemies
         elseif players[pindex].nearby.category == 8 then
            ents = players[pindex].nearby.other
         end
   
         if players[pindex].nearby.selection < #ents[players[pindex].nearby.index].ents then
            players[pindex].nearby.selection = players[pindex].nearby.selection + 1
         else
            game.get_player(pindex).play_sound{path = "player-mine"}
            players[pindex].nearby.selection = #ents[players[pindex].nearby.index].ents
         end
      end
      scan_index(pindex)
   end
end)

--Repeats the last thing read out. Not just the scanner.
script.on_event("repeat-last-spoken", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   repeat_last_spoken(pindex)
end)

--Calls function to notify if items are being picked up via vanilla F key.
script.on_event("pickup-items-info", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   read_item_pickup_state(pindex)
end)

function read_item_pickup_state(pindex)
   if players[pindex].in_menu then
      printout("Cannot pickup items while in a menu",pindex)
      return
   end
   local p = game.get_player(pindex)
   local result = ""
   local check_last_pickup = false
   local nearby_belts = p.surface.find_entities_filtered{position = p.position, radius = 1.25, type = "transport-belt"}
   local nearby_ground_items = p.surface.find_entities_filtered{position = p.position, radius = 1.25, name = "item-on-ground"}
   rendering.draw_circle{color = {0.3, 1, 0.3},radius = 1.25,width = 1,target = p.position, surface = p.surface,time_to_live = 60, draw_on_ground = true}
   --Check if there is a belt within n tiles
   if #nearby_belts > 0 then
      result = "Picking up "
      --Check contents being picked up
      local ent = nearby_belts[1]
      if ent == nil or not ent.valid then
         result = result .. " from nearby belts"
         printout(result,pindex)
         return 
      end
      local left = ent.get_transport_line(1).get_contents()
      local right = ent.get_transport_line(2).get_contents()

      for name, count in pairs(right) do
         if left[name] ~= nil then
            left[name] = left[name] + count
         else
            left[name] = count
         end
      end
      local contents = {}
      for name, count in pairs(left) do
         table.insert(contents, {name = name, count = count})
      end
      table.sort(contents, function(k1, k2)
         return k1.count > k2.count
      end)
      if #contents > 0 then
         result = result .. contents[1].name
         if #contents > 1 then
            result = result .. ", and " .. contents[2].name
            if #contents > 2 then
               result = result .. ", and other item types " 
            end
         end
      end
      result = result .. " from nearby belts"
   --Check if there are ground items within n tiles   
   elseif #nearby_ground_items > 0 then
      result = "Picking up "
      if nearby_ground_items[1] and nearby_ground_items[1].valid then
         result = result .. nearby_ground_items[1].stack.name 
      end
      result = result .. " from ground, and possibly more items "
   else
      result = "No items within range to pick up"
   end
   printout(result,pindex)
end

--Save info about last item pickup and draw radius
script.on_event(defines.events.on_picked_up_item, function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local p = game.get_player(pindex)
   rendering.draw_circle{color = {0.3, 1, 0.3},radius = 1.25,width = 1,target = p.position, surface = p.surface,time_to_live = 10, draw_on_ground = true}
   players[pindex].last_pickup_tick = event.tick
   players[pindex].last_item_picked_up = event.item_stack.name
end)

--Reads other entities on the same tile? Note: Possibly unneeded
script.on_event("tile-cycle", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      tile_cycle(pindex)
   end
end)

script.on_event("open-inventory", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   elseif (players[pindex].in_menu) or players[pindex].last_menu_toggle_tick == event.tick then
      return
   elseif not (players[pindex].in_menu) then
      open_player_inventory(event.tick,pindex)
   end
end)

--Sets up mod character menus. Cannot actually open the character GUI.
function open_player_inventory(tick,pindex)
   game.get_player(pindex).play_sound{path = "Open-Inventory-Sound"}
   players[pindex].last_menu_toggle_tick = tick 
   players[pindex].in_menu = true
   players[pindex].menu="inventory"
   players[pindex].inventory.lua_inventory = game.get_player(pindex).get_main_inventory()
   players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
   players[pindex].inventory.index = 1
   read_inventory_slot(pindex, "Inventory, ")
   players[pindex].crafting.lua_recipes = get_recipes(pindex, game.get_player(pindex).character)
   players[pindex].crafting.max = #players[pindex].crafting.lua_recipes
   players[pindex].crafting.category = 1
   players[pindex].crafting.index = 1
   players[pindex].technology.category = 1
   players[pindex].technology.lua_researchable = {}
   players[pindex].technology.lua_unlocked = {}
   players[pindex].technology.lua_locked = {}
   -- Create technologies list
   for i, tech in pairs(game.get_player(pindex).force.technologies) do
      if tech.researched then
         table.insert(players[pindex].technology.lua_unlocked, tech)
      else
         local check = true
         for i1, preq in pairs(tech.prerequisites) do
            if not(preq.researched) then
               check = false
            end
         end
         if check then
            table.insert(players[pindex].technology.lua_researchable, tech)
         else
            local check = false
            for i1, preq in pairs(tech.prerequisites) do
               if preq.researched then
                  check = true
               end
            end
            if check then
               table.insert(players[pindex].technology.lua_locked, tech)
            end
         end
      end
   end
end

script.on_event("close-menu", function(event)--close_menu, menu closed
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   players[pindex].move_queue = {}
   if not players[pindex].in_menu or players[pindex].last_menu_toggle_tick == event.tick then
      return
   elseif players[pindex].in_menu and players[pindex].menu ~= "prompt" then
      printout("Menu closed.", pindex)
      if players[pindex].menu == "inventory" or players[pindex].menu == "crafting" or players[pindex].menu == "technology" or players[pindex].menu == "crafting_queue" or players[pindex].menu == "warnings" then--**laterdo open close inv sounds in other menus?
         game.get_player(pindex).play_sound{path="Close-Inventory-Sound"}
      end
      players[pindex].last_menu_toggle_tick = event.tick 
      close_menu_resets(pindex)
   end
end)

function close_menu_resets(pindex)
   game.get_player(pindex).game_view_settings.update_entity_selection = true
   if players[pindex].menu == "travel" then
      game.get_player(pindex).gui.screen["travel"].destroy()
      players[pindex].cursor_pos = center_of_tile(players[pindex].position)
      cursor_highlight(pindex, nil, "train-visualization")
   elseif players[pindex].menu == "structure-travel" then
      game.get_player(pindex).gui.screen["structure-travel"].destroy()
   elseif players[pindex].menu == "rail_builer" then
      rail_builder_close(pindex, false)
   elseif players[pindex].menu == "train_menu" then
      train_menu_close(pindex, false)
   elseif players[pindex].menu == "train_stop_menu" then
      train_stop_menu_close(pindex, false)
   elseif players[pindex].menu == "roboport_menu" then
      roboport_menu_close(pindex)
   end
   
   players[pindex].in_menu = false
   players[pindex].menu = "none"
   players[pindex].entering_search_term = false
   players[pindex].menu_search_index = nil
   players[pindex].menu_search_index_2 = nil
   players[pindex].item_selection = false
   players[pindex].item_cache = {}
   players[pindex].item_selector = {index = 0, group = 0, subgroup = 0}
   players[pindex].building = {
      index = 0,
      ent = nil,
      sectors = nil,
      sector = 0,
      recipe_selection = false,
      item_selection = false,
      category = 0,
      recipe = nil,
      recipe_list = nil
   }
end

script.on_event("read-menu-name", function(event)--read_menu_name
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local menu_name = "menu "
   if players[pindex].in_menu == false then
      menu_name = "no menu"
   elseif players[pindex].menu ~= nil and players[pindex].menu ~= "" then
      menu_name = players[pindex].menu
      if players[pindex].menu == "building" then
         --Name the building
         local pb = players[pindex].building 
         menu_name = menu_name .. " " .. pb.ent.name
         --Name the sector
         if pb.sectors and pb.sectors[pb.sector] and pb.sectors[pb.sector].name ~= nil then
            menu_name = menu_name .. ", " .. pb.sectors[pb.sector].name
         elseif players[pindex].building.recipe_selection == true then
            menu_name = menu_name .. ", recipe selection"
         else
            menu_name = menu_name .. ", other section"
         end
      end
   else
      menu_name = "unknown menu"
   end
   printout(menu_name,pindex)
end)

script.on_event("quickbar-1", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(1,pindex)
   end
end)

script.on_event("quickbar-2", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(2,pindex)
   end
end)

script.on_event("quickbar-3", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(3,pindex)
   end
end)

script.on_event("quickbar-4", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(4,pindex)
   end
end)

script.on_event("quickbar-5", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(5,pindex)
   end
end)

script.on_event("quickbar-6", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(6,pindex)
   end
end)

script.on_event("quickbar-7", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(7,pindex)
   end
end)

script.on_event("quickbar-8", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(8,pindex)
   end
end)

script.on_event("quickbar-9", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(9,pindex)
   end
end)

script.on_event("quickbar-10", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) then
      read_quick_bar(10,pindex)
   end
end)

local set_quickbar_names = {}
for i = 1,10 do
   table.insert(set_quickbar_names,"set-quickbar-"..i)
end
script.on_event(set_quickbar_names,function(event)--all 10 quickbar setting event handlers
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].menu == "inventory" then
      local num=tonumber(string.sub(event.input_name,-1))
      if num == 0 then
         num = 10
      end
      set_quick_bar(num, pindex)
   end
end)

script.on_event("switch-menu-or-gun", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu ~= "prompt" then
      game.get_player(pindex).play_sound{path="Change-Menu-Tab-Sound"}
      if players[pindex].menu == "building" then
         players[pindex].building.index = 1
         players[pindex].building.category = 1
         players[pindex].building.recipe_selection = false

         players[pindex].building.sector = players[pindex].building.sector + 1 --Change sector
         players[pindex].building.item_selection = false
         players[pindex].item_selection = false
         players[pindex].item_cache = {}
         players[pindex].item_selector = {
            index = 0,
            group = 0,
            subgroup = 0
         }

         if players[pindex].building.sector <= #players[pindex].building.sectors then
            read_building_slot(pindex, true)
--            if inventory == players[pindex].building.sectors[players[pindex].building.sector+1].inventory then
--               printout("Big Problem!", pindex)
  --          end
         elseif players[pindex].building.recipe_list == nil then
            if players[pindex].building.sector == (#players[pindex].building.sectors + 1) then
			   read_inventory_slot(pindex, "Player Inventory, ")
            else
               players[pindex].building.sector = 1
               read_building_slot(pindex, true)
            end
         else
            if players[pindex].building.sector == #players[pindex].building.sectors + 1 then     --Recipe selection sector
               read_building_recipe(pindex, "Select a Recipe, ")
            elseif players[pindex].building.sector == #players[pindex].building.sectors + 2 then --Player inventory sector
               read_inventory_slot(pindex, "Player Inventory, ")
            else
               players[pindex].building.sector = 1
               read_building_slot(pindex, true)
            end
         end
      elseif players[pindex].menu == "inventory" then 
         players[pindex].menu = "crafting"
		 read_crafting_slot(pindex, "Crafting, ")
      elseif players[pindex].menu == "crafting" then 
         players[pindex].menu = "crafting_queue"
         load_crafting_queue(pindex)
		 read_crafting_queue(pindex, "Crafting queue, ")
      elseif players[pindex].menu == "crafting_queue" then
         players[pindex].menu = "technology"
		 read_technology_slot(pindex, "Technology, Researchable Technologies, ")
      elseif players[pindex].menu == "technology" then
         players[pindex].menu = "inventory"
         read_inventory_slot(pindex, "Inventory, ")
      elseif players[pindex].menu == "belt" then
         players[pindex].belt.index = 1
         players[pindex].belt.sector = players[pindex].belt.sector + 1
         if players[pindex].belt.sector == 5 then
            players[pindex].belt.sector = 1
         end
         local sector = players[pindex].belt.sector
         if sector == 1 then
            printout("Local Lanes", pindex)
         elseif sector == 2 then
            printout("Total Lanes", pindex)
         elseif sector == 3 then
            printout("Downstream lanes", pindex)
         elseif sector == 4 then
            printout("Upstream Lanes", pindex)
         end
      elseif players[pindex].menu == "warnings" then
         players[pindex].warnings.sector = players[pindex].warnings.sector + 1
         if players[pindex].warnings.sector > 3 then
            players[pindex].warnings.sector = 1
         end
         if players[pindex].warnings.sector == 1 then
            printout("Short Range: " .. players[pindex].warnings.short.summary, pindex)
         elseif players[pindex].warnings.sector == 2 then
            printout("Medium Range: " .. players[pindex].warnings.medium.summary, pindex)
         elseif players[pindex].warnings.sector == 3 then
            printout("Long Range: " .. players[pindex].warnings.long.summary, pindex)
         end

      end
   end
   
   --Gun related changes (this seems to run before the actual switch happens so even when we write the new index, it will change, so we need to be predictive)
   local p = game.get_player(pindex)
   local guns_inv = p.get_inventory(defines.inventory.character_guns)
   local ammo_inv = game.get_player(pindex).get_inventory(defines.inventory.character_ammo)
   local result = ""
   local switched_index = -2

   if players[pindex].in_menu then
      --switch_success = swap_weapon_backward(pindex,true)
      switched_index = swap_weapon_backward(pindex,true)
      return 
   else
      switched_index = swap_weapon_forward(pindex,false)
   end
   
   --Declare the selected weapon
   local gun_index = switched_index
   local ammo_stack = nil
   local gun_stack = nil 
   
   if gun_index < 1 then
      result = "No ready weapons"
   else
      local ammo_stack = ammo_inv[gun_index]
      local gun_stack  = guns_inv[gun_index]
      --game.print("print " .. gun_index)--
      result = gun_stack.name .. " with " .. ammo_stack.count .. " " .. ammo_stack.name .. "s "
   end
   
   if not players[pindex].in_menu then
      --p.play_sound{path = "Inventory-Move"}
      printout(result,pindex)
   end
end)

script.on_event("reverse-switch-menu-or-gun", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu ~= "prompt" then
      game.get_player(pindex).play_sound{path="Change-Menu-Tab-Sound"}
      if players[pindex].menu == "building" then
         players[pindex].building.category = 1
         players[pindex].building.recipe_selection = false
         players[pindex].building.index = 1

         players[pindex].building.sector = players[pindex].building.sector - 1
         players[pindex].building.item_selection = false
         players[pindex].item_selection = false
         players[pindex].item_cache = {}
         players[pindex].item_selector = {
            index = 0,
            group = 0,
            subgroup = 0
         }

         if players[pindex].building.sector < 1 then
            if players[pindex].building.recipe_list == nil then
               players[pindex].building.sector = #players[pindex].building.sectors + 1
            else
               players[pindex].building.sector = #players[pindex].building.sectors + 2
            end
            read_inventory_slot(pindex, "Player Inventory, ")
            
         elseif players[pindex].building.sector <= #players[pindex].building.sectors then
            read_building_slot(pindex, true)
         elseif players[pindex].building.recipe_list == nil then
            if players[pindex].building.sector == (#players[pindex].building.sectors + 1) then
               read_inventory_slot(pindex, "Player Inventory, ")
            end
         else
            if players[pindex].building.sector == #players[pindex].building.sectors + 1 then
               read_building_recipe(pindex, "Select a Recipe, ")
            elseif players[pindex].building.sector == #players[pindex].building.sectors + 2 then
               read_inventory_slot(pindex, "Player Inventory, ")
            end
         end


      elseif players[pindex].menu == "inventory" then
         players[pindex].menu = "technology"
         read_technology_slot(pindex, "Technology, Researchable Technologies, ")
      elseif players[pindex].menu == "crafting_queue" then
         players[pindex].menu = "crafting"
         read_crafting_slot(pindex, "Crafting, ") 
      elseif players[pindex].menu == "technology" then 
         players[pindex].menu = "crafting_queue"
         load_crafting_queue(pindex)
		 read_crafting_queue(pindex, "Crafting queue, ")
      elseif players[pindex].menu == "crafting" then
         players[pindex].menu = "inventory"
         read_inventory_slot(pindex, "Inventory, ")
      elseif players[pindex].menu == "belt" then
         players[pindex].belt.index = 1
         players[pindex].belt.sector = players[pindex].belt.sector - 1
         if players[pindex].belt.sector == 0 then
            players[pindex].belt.sector = 4
         end
         local sector = players[pindex].belt.sector
         if sector == 1 then
            printout("Local Lanes", pindex)
         elseif sector == 2 then
            printout("Total Lanes", pindex)
         elseif sector == 3 then
            printout("Downstream lanes", pindex)
         elseif sector == 4 then
            printout("Upstream Lanes", pindex)
         end
      elseif players[pindex].menu == "warnings" then
         players[pindex].warnings.sector = players[pindex].warnings.sector - 1
         if players[pindex].warnings.sector < 1 then
            players[pindex].warnings.sector = 3
         end
         if players[pindex].warnings.sector == 1 then
            printout("Short Range: " .. players[pindex].warnings.short.summary, pindex)
         elseif players[pindex].warnings.sector == 2 then
            printout("Medium Range: " .. players[pindex].warnings.medium.summary, pindex)
         elseif players[pindex].warnings.sector == 3 then
            printout("Long Range: " .. players[pindex].warnings.long.summary, pindex)
         end

      end
   end
   
   --Gun related changes (Vanilla Factorio DOES NOT have shift + tab weapon revserse switching, so we add it without prediction needed)
   local p = game.get_player(pindex)
   local guns_inv = p.get_inventory(defines.inventory.character_guns)
   local ammo_inv = game.get_player(pindex).get_inventory(defines.inventory.character_ammo)
   local result = ""
   local switched_index = -2

   if players[pindex].in_menu then
      --do nothing
      return 
   else
      switched_index = swap_weapon_backward(pindex,true)
   end
   
   --Declare the selected weapon
   local gun_index = switched_index
   local ammo_stack = nil
   local gun_stack = nil 
   
   if gun_index < 1 then
      result = "No ready weapons"
   else
      local ammo_stack = ammo_inv[gun_index]
      local gun_stack  = guns_inv[gun_index]
      --game.print("print " .. gun_index)--
      result = gun_stack.name .. " with " .. ammo_stack.count .. " " .. ammo_stack.name .. "s "
   end
   
   if not players[pindex].in_menu then
      p.play_sound{path = "Inventory-Move"}
      printout(result,pindex)
   end
end)

function swap_weapon_forward(pindex, write_to_character)
   local p = game.get_player(pindex)
   local gun_index = p.character.selected_gun_index
   local guns_inv = p.get_inventory(defines.inventory.character_guns)
   local ammo_inv = game.get_player(pindex).get_inventory(defines.inventory.character_ammo)
   
   --Simple index increment (not needed)
   gun_index = gun_index + 1
   if gun_index > 3 then 
      gun_index = 1
   end
   --game.print("start " .. gun_index)--
   
   --Increment again if the new index has no guns or no ammo
   local ammo_stack = ammo_inv[gun_index]
   local gun_stack  = guns_inv[gun_index]
   local tries = 0
   while tries < 4 and (ammo_stack == nil or not ammo_stack.valid_for_read or not ammo_stack.valid or gun_stack == nil or not gun_stack.valid_for_read or not gun_stack.valid) do
      gun_index = gun_index + 1
      if gun_index > 3 then 
         gun_index = 1
      end
      ammo_stack = ammo_inv[gun_index]
      gun_stack  = guns_inv[gun_index]
      tries = tries + 1
   end
   
   if tries > 3 then
      --game.print("error " .. gun_index)--
      return -1
   end
   
   if write_to_character then
      p.character.selected_gun_index = gun_index
   end
   --game.print("end " .. gun_index)--
   return gun_index
end

function swap_weapon_backward(pindex, write_to_character)
   local p = game.get_player(pindex)
   local gun_index = p.character.selected_gun_index
   local guns_inv = p.get_inventory(defines.inventory.character_guns)
   local ammo_inv = game.get_player(pindex).get_inventory(defines.inventory.character_ammo)
   
   --Simple index increment (not needed)
   gun_index = gun_index - 1
   if gun_index < 1 then 
      gun_index = 3
   end
   
   --Increment again if the new index has no guns or no ammo
   local ammo_stack = ammo_inv[gun_index]
   local gun_stack  = guns_inv[gun_index]
   local tries = 0
   while tries < 4 and (ammo_stack == nil or not ammo_stack.valid_for_read or not ammo_stack.valid or gun_stack == nil or not gun_stack.valid_for_read or not gun_stack.valid) do
      gun_index = gun_index - 1
      if gun_index < 1 then 
         gun_index = 3
      end
      ammo_stack = ammo_inv[gun_index]
      gun_stack  = guns_inv[gun_index]
      tries = tries + 1
   end
   
   if tries > 3 then
      return -1
   end
   
   if write_to_character then
      p.character.selected_gun_index = gun_index
   end
   return gun_index
end

function play_mining_sound(pindex)
   local player= game.players[pindex]
   --game.print("1",{volume_modifier=0})--**
   if player and player.mining_state.mining and player.selected and player.selected.valid then 
      --game.print("2",{volume_modifier=0})--
      if player.selected.prototype.is_building then
         player.play_sound{path = "player-mine"}
         --game.print("3A",{volume_modifier=0})--
      else
         player.play_sound{path = "player-mine"}--Mine other things, eg. character corpses, laterdo new sound
         --game.print("3B",{volume_modifier=0})--
      end
      schedule(25, "play_mining_sound", pindex)
   end
end

--Creates sound effects for vanilla mining. Needs to be same key as vanilla mining key. 
script.on_event("mine-access-sounds", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) and not players[pindex].vanilla_mode then   
      target(pindex)
      local ent = get_selected_ent(pindex)
      --if ent and (ent.prototype.mineable_properties.products == nil or ent.prototype.mineable_properties.products[1].name == ent.name) then
      if ent and ent.valid and (ent.prototype.mineable_properties.products ~= nil) then
         game.get_player(pindex).play_sound{path = "player-mine"}
         schedule(25, "play_mining_sound", pindex)
      elseif ent and ent.valid and ent.name == "character-corpse" then
         printout("Collecting items ", pindex)
      end
   end
end)

--Mines tiles such as stone brick or concrete within the cursor area, including enlarged cursors
script.on_event("mine-tiles", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu) and not players[pindex].vanilla_mode then         
      --Mine tiles around the cursor
      local stack = game.get_player(pindex).cursor_stack
      local surf = game.get_player(pindex).surface
      if stack and stack.valid_for_read and stack.valid and stack.prototype.place_as_tile_result ~= nil then
         players[pindex].allow_reading_flying_text = false
         local c_pos = players[pindex].cursor_pos
         local c_size = players[pindex].cursor_size
         local left_top = {x = math.floor(c_pos.x - c_size), y = math.floor(c_pos.y - c_size)}
         local right_bottom = {x = math.floor(c_pos.x + 1 + c_size), y = math.floor(c_pos.y + 1 + c_size)}
         local tiles = surf.find_tiles_filtered{area = {left_top, right_bottom}}
         for i , tile in ipairs(tiles) do
            local mined = game.get_player(pindex).mine_tile(tile)
            if mined then
               game.get_player(pindex).play_sound{path = "entity-mined/stone-furnace"}
            end
         end
      end
   end
end)

--Mines groups of entities depending on the name or type. Includes trees and rocks, rails.
script.on_event("mine-area", function(event) 
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu then
      return
   end
   local ent =  get_selected_ent(pindex)
   local cleared_count = 0
   local cleared_total = 0
   local comment = ""
   
   --Check if within reach
   if ent ~= nil and ent.valid and util.distance(game.get_player(pindex).position, ent.position) > game.get_player(pindex).reach_distance 
   or util.distance(game.get_player(pindex).position, players[pindex].cursor_pos) > game.get_player(pindex).reach_distance then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      printout("This area is out of player reach",pindex)
      return
   end
   
   players[pindex].allow_reading_flying_text = false
   if ent then 
      local surf = ent.surface
      local pos = ent.position
      if ent.type == "tree" or ent.name == "rock-big" or ent.name == "rock-huge" or ent.name == "sand-rock-big" or ent.name == "item-on-ground" then
         --Obstacles within 5 tiles: trees and rocks and ground items
         game.get_player(pindex).play_sound{path = "player-mine"}
         cleared_count, comment = clear_obstacles_in_circle(pos, 5, pindex)
      elseif ent.name == "straight-rail" or ent.name == "curved-rail" then
         --Rails within 5 tiles (and their signals)
         local rails = surf.find_entities_filtered{position = pos, radius = 7, name = {"straight-rail","curved-rail"}}
         for i,rail in ipairs(rails) do
            mine_signals(rail,pindex)
            game.get_player(pindex).play_sound{path = "entity-mined/straight-rail"}
            game.get_player(pindex).mine_entity(rail,true)
            cleared_count = cleared_count + 1
         end
      else
         --Check if it is a remnant ent, clear obstacles
         local ent_is_remnant = false
         local remnant_names = {"tree-01-stump","tree-02-stump","tree-03-stump","tree-04-stump","tree-05-stump","tree-06-stump","tree-07-stump","tree-08-stump","tree-09-stump","small-scorchmark","small-scorchmark-tintable","medium-scorchmark","medium-scorchmark-tintable","big-scorchmark","big-scorchmark-tintable","huge-scorchmark","huge-scorchmark-tintable"}
         for i,name in ipairs(remnant_names) do 
            if ent.name == name then
               ent_is_remnant = true
            end
         end
         if ent_is_remnant then
            game.get_player(pindex).play_sound{path = "player-mine"}
            cleared_count, comment = clear_obstacles_in_circle(players[pindex].cursor_pos, 5, pindex) 
         end
      end
   else
      --For empty tiles, clear obstacles
      game.get_player(pindex).play_sound{path = "player-mine"}
      cleared_count, comment = clear_obstacles_in_circle(players[pindex].cursor_pos, 5, pindex) 
   end
   cleared_total = cleared_total + cleared_count
   
   --Also, if cut-paste tool in hand, mine every non-resource entity in the area that you can. 
   local p = game.get_player(pindex)
   local stack = p.cursor_stack
   if stack and stack.valid_for_read and stack.name == "cut-paste-tool" then
      players[pindex].allow_reading_flying_text = false
      local all_ents = p.surface.find_entities_filtered{position = p.position, radius = 5, force = {p.force, "neutral"}}
      for i,ent in ipairs(all_ents) do
         if ent and ent.valid then
            local name = ent.name
            game.get_player(pindex).play_sound{path = "player-mine"}
            if try_to_mine_with_sound(ent,pindex) then
               cleared_total = cleared_total + 1
            end
         end
      end
   end
   printout(" Cleared away " .. cleared_total .. " objects. ", pindex)
end)

--Cut-paste-tool. NOTE: This keybind needs to be the same as that for the cut paste tool (default CONTROL + X). laterdo maybe keybind to game control somehow
script.on_event("cut-paste-tool-comment", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local stack = game.get_player(pindex).cursor_stack
   if stack == nil then
      --(do nothing when the cut paste tool is not enabled)
   elseif stack and stack.valid_for_read and stack.name == "cut-paste-tool" then
      printout("To disable this tool empty the hand, by pressing SHIFT + Q",pindex)
   end
end)

--Mines an entity with the right sound
function try_to_mine_with_sound(ent,pindex)
   if ent ~= nil and ent.valid and ((ent.destructible and ent.type ~= "resource") or ent.name == "item-on-ground") then 
	 local ent_name = ent.name
	 if game.get_player(pindex).mine_entity(ent,false) and game.is_valid_sound_path("entity-mined/" .. ent_name) then 
	    game.get_player(pindex).play_sound{path = "entity-mined/" .. ent_name} 
		return true
	 else
      return false
	 end
   end
end

--Mines all trees and rocks and ground items in a selected circular area. Useful when placing structures. Forces mining. laterdo add deleting stumps maybe but they do fade away eventually 
function clear_obstacles_in_circle(position, radius, pindex)
   local surf = game.get_player(pindex).surface
   local comment = ""
   local trees_cleared = 0
   local rocks_cleared = 0
   local remnants_cleared = 0
   local ground_items_cleared = 0
   players[pindex].allow_reading_flying_text = false
   
   --Find and mine trees
   local trees = surf.find_entities_filtered{position = position, radius = radius, type = "tree"}
   for i,tree_ent in ipairs(trees) do
      rendering.draw_circle{color = {1, 0, 0},radius = 1,width = 1,target = tree_ent.position,surface = tree_ent.surface,time_to_live = 60}
      game.get_player(pindex).mine_entity(tree_ent,true)
	  trees_cleared = trees_cleared + 1
   end
   
   --Find and mine rocks. Note that they are resource entities with specific names
   local resources = surf.find_entities_filtered{position = position, radius = radius, name = {"rock-big","rock-huge","sand-rock-big"}}
   for i,resource_ent in ipairs(resources) do
      if resource_ent ~= nil and resource_ent.valid then
         rendering.draw_circle{color = {1, 0, 0},radius = 2,width = 2,target = resource_ent.position,surface = resource_ent.surface,time_to_live = 60}
         game.get_player(pindex).mine_entity(resource_ent,true) 
         rocks_cleared = rocks_cleared + 1
      end
   end
   
   --Find and mine corpse entities such as building remnants
   local corpse_ents = surf.find_entities_filtered{position = position, radius = radius, name = {"tree-01-stump","tree-02-stump","tree-03-stump","tree-04-stump","tree-05-stump","tree-06-stump","tree-07-stump","tree-08-stump","tree-09-stump","small-scorchmark","small-scorchmark-tintable","medium-scorchmark","medium-scorchmark-tintable","big-scorchmark","big-scorchmark-tintable","huge-scorchmark","huge-scorchmark-tintable"}}
   for i,corpse_ent in ipairs(corpse_ents) do
      if corpse_ent ~= nil and corpse_ent.valid then
         rendering.draw_circle{color = {1, 0, 0},radius = 2,width = 2,target = corpse_ent.position,surface = corpse_ent.surface,time_to_live = 60}
         corpse_ent.destroy{}
         remnants_cleared = remnants_cleared + 1
      end
   end
   --game.get_player(pindex).print("remnants cleared: " .. remnants_cleared)--debug
   
   --Find and mine items on the ground
   local ground_items = surf.find_entities_filtered{position = position, radius = 5, name = "item-on-ground"}
   for i,ground_item in ipairs(ground_items) do
      rendering.draw_circle{color = {1, 0, 0},radius = 0.25,width = 2,target = ground_item.position,surface = surf,time_to_live = 60}
      game.get_player(pindex).mine_entity(ground_item,true)
      ground_items_cleared = ground_items_cleared + 1
   end
         
   if trees_cleared + rocks_cleared + ground_items_cleared + remnants_cleared > 0 then
      comment = "cleared " .. trees_cleared .. " trees and " .. rocks_cleared .. " rocks and " .. remnants_cleared .. " remnants and " .. ground_items_cleared .. " ground items "
   end
   rendering.draw_circle{color = {0, 1, 0},radius = radius,width = radius,target = position,surface = surf,time_to_live = 60}
   return (trees_cleared + rocks_cleared + remnants_cleared + ground_items_cleared), comment
end

--Left click actions in menus (click_menu)
script.on_event("click-menu", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].last_click_tick == event.tick then
      return
   end
   if players[pindex].in_menu then
      players[pindex].last_click_tick = event.tick
      if players[pindex].menu == "inventory" then
         game.get_player(pindex).play_sound{path = "utility/inventory_click"}
         local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
         game.get_player(pindex).cursor_stack.swap_stack(stack)
            players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
         --read_inventory_slot(pindex)
      elseif players[pindex].menu == "crafting" then
         local T = {
            count = 1,
         recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index],
            silent = false
         }
         local count = game.get_player(pindex).begin_crafting(T)
         if count > 0 then
            printout("Started crafting " .. count .. " " .. T.recipe.name, pindex)
         else
            printout("Not enough materials", pindex)
         end

      elseif players[pindex].menu == "crafting_queue" then
         load_crafting_queue(pindex)
         if players[pindex].crafting_queue.max >= 1 then
            local T = {
            index = players[pindex].crafting_queue.index,
               count = 1
            }
            game.get_player(pindex).cancel_crafting(T)
            load_crafting_queue(pindex)
            read_crafting_queue(pindex)
         end
         
      elseif players[pindex].menu == "building" then
         local sectors_i = players[pindex].building.sectors[players[pindex].building.sector]
         if players[pindex].building.sector <= #players[pindex].building.sectors and #sectors_i.inventory > 0  then
            if sectors_i.name == "Fluid" then
               return
            elseif sectors_i.name == "Filters" then
               if players[pindex].building.index == #sectors_i.inventory then
               if players[pindex].building.ent == nil or not players[pindex].building.ent.valid then
                  if players[pindex].building.ent == nil then 
                     printout("Nil entity", pindex)
                  else
                     printout("Invalid Entity", pindex)
                  end
                  return
               end
                  if players[pindex].building.ent.inserter_filter_mode == "whitelist" then
                     players[pindex].building.ent.inserter_filter_mode = "blacklist"
                  else
                     players[pindex].building.ent.inserter_filter_mode = "whitelist"
                  end
                  sectors_i.inventory[players[pindex].building.index] = players[pindex].building.ent.inserter_filter_mode 
                  read_building_slot(pindex,false)
               elseif players[pindex].building.item_selection then
                  if players[pindex].item_selector.group == 0 then
                     players[pindex].item_selector.group = players[pindex].item_selector.index
                     players[pindex].item_cache = get_iterable_array(players[pindex].item_cache[players[pindex].item_selector.group].subgroups)
                     prune_item_groups(players[pindex].item_cache)

                     players[pindex].item_selector.index = 1
                     read_item_selector_slot(pindex)
                  elseif players[pindex].item_selector.subgroup == 0 then
                     players[pindex].item_selector.subgroup = players[pindex].item_selector.index
                     local prototypes = game.get_filtered_item_prototypes{{filter="subgroup",subgroup = players[pindex].item_cache[players[pindex].item_selector.index].name}}
                     players[pindex].item_cache = get_iterable_array(prototypes)
                     players[pindex].item_selector.index = 1
                     read_item_selector_slot(pindex)
                  else
                     players[pindex].building.ent.set_filter(players[pindex].building.index, players[pindex].item_cache[players[pindex].item_selector.index].name)
                     sectors_i.inventory[players[pindex].building.index] = players[pindex].building.ent.get_filter(players[pindex].building.index)
                     printout("Filter set.", pindex)
                     players[pindex].building.item_selection = false
                     players[pindex].item_selection = false
                  end
               else
                  players[pindex].item_selector.group = 0
                  players[pindex].item_selector.subgroup = 0
                  players[pindex].item_selector.index = 1
                     players[pindex].item_selection = true
                  players[pindex].building.item_selection = true
                  players[pindex].item_cache = get_iterable_array(game.item_group_prototypes)
                     prune_item_groups(players[pindex].item_cache)                  
                  read_item_selector_slot(pindex)
               end
               return
            end
            local stack = sectors_i.inventory[players[pindex].building.index]
            local cursor_stack = game.get_player(pindex).cursor_stack
            --If both stacks have the same item, do a transfer
            if cursor_stack.valid_for_read and stack.valid_for_read and cursor_stack.name == stack.name then
               stack.transfer_stack(cursor_stack)
               if sectors_i.name == "Modules" and cursor_stack.is_module then
                  printout(" Only one module can be added per module slot " , pindex)
               else
                  printout(" Adding to stack of " .. cursor_stack.name , pindex)
               end
               return
            end
            --Special case for filling module slots
            if sectors_i.name == "Modules" and cursor_stack ~= nil and cursor_stack.valid_for_read and cursor_stack.is_module then
               local p_inv = game.get_player(pindex).get_main_inventory()
               local result = ""
               if stack.valid_for_read and stack.count > 0 then
                  if p_inv.count_empty_stacks() < 2 then
                     printout(" Error: At least two empty player inventory slots needed", pindex)
                     return
                  else
                     result = "Collected " .. stack.name .. " and "
                     p_inv.insert(stack)
                     stack.clear()
                  end
               end
               stack = sectors_i.inventory[players[pindex].building.index]
               if (stack == nil or stack.count == 0) and sectors_i.inventory.can_insert(cursor_stack) then
                  local module_name = cursor_stack.name
                  local successful = sectors_i.inventory[players[pindex].building.index].set_stack({name = module_name, count = 1})
                  if not successful then
                     printout(" Failed to add module ", pindex)
                     return
                  end 
                  cursor_stack.count = cursor_stack.count - 1
                  printout(result .. "added " .. module_name, pindex)
                  return
               else
                  printout(" Failed to add module ", pindex)
                  return
               end
            end
            --Try to swap stacks and report if there is an error
            if cursor_stack.swap_stack(stack) then
               game.get_player(pindex).play_sound{path = "utility/inventory_click"}
--             read_building_slot(pindex,false)
            else
               local name = "This item"
               if (stack == nil or not stack.valid_for_read) and (cursor_stack == nil or not cursor_stack.valid_for_read) then
                  printout("Empty", pindex)
                  return
               end
               if cursor_stack.valid_for_read then
                  name = cursor_stack.name
               end
               printout("Cannot insert " .. name .. " in this slot", pindex)
            end
         elseif players[pindex].building.recipe_list == nil then
            game.get_player(pindex).play_sound{path = "utility/inventory_click"}
            local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
            game.get_player(pindex).cursor_stack.swap_stack(stack)
            players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
--          read_inventory_slot(pindex)
         else
            if players[pindex].building.sector == #players[pindex].building.sectors + 1 then --Building recipe selection
               if players[pindex].building.recipe_selection then
                  if not(pcall(function()
                     players[pindex].building.recipe = players[pindex].building.recipe_list[players[pindex].building.category][players[pindex].building.index]
                     if players[pindex].building.ent.valid then
                        players[pindex].building.ent.set_recipe(players[pindex].building.recipe)
                     end
                     players[pindex].building.recipe_selection = false
                     players[pindex].building.index = 1
                     printout("Selected", pindex)
                     game.get_player(pindex).play_sound{path = "utility/inventory_click"}
                     --Open GUI if not already
                     local p = game.get_player(pindex)
                     if players[pindex].building.ent.valid then 
                        --p.opened = nil
                        --p.opened = players[pindex].building.ent--bug** doesnt work 
                     end
                  end)) then
                     printout("For this building, recipes are selected automatically based on the input item, this menu is for information only.", pindex)
                  end
               elseif #players[pindex].building.recipe_list > 0 then
               game.get_player(pindex).play_sound{path = "utility/inventory_click"}
                  players[pindex].building.recipe_selection = true
                  players[pindex].building.category = 1
                  players[pindex].building.index = 1
                  read_building_recipe(pindex)
               else
                  printout("No recipes unlocked for this building yet.", pindex)
               end
            else
               game.get_player(pindex).play_sound{path = "utility/inventory_click"}
               local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
               game.get_player(pindex).cursor_stack.swap_stack(stack)

                  players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
----               read_inventory_slot(pindex)
            end

         end
         
      elseif players[pindex].menu == "technology" then
         local techs = {}
         if players[pindex].technology.category == 1 then
            techs = players[pindex].technology.lua_researchable
         elseif players[pindex].technology.category == 2 then
            techs = players[pindex].technology.lua_locked
         elseif players[pindex].technology.category == 3 then
            techs = players[pindex].technology.lua_unlocked
         end
            
         if next(techs) ~= nil and players[pindex].technology.index > 0 and players[pindex].technology.index <= #techs then
            if game.get_player(pindex).force.add_research(techs[players[pindex].technology.index]) then
               printout("Research started.", pindex)
            else
               printout("Research locked, first complete the prerequisites.", pindex)
            end
         end
         
      elseif players[pindex].menu == "pump" then
         if players[pindex].pump.index == 0 then
            printout("Move up and down to select a location.", pindex)
            return
         end
         local entry = players[pindex].pump.positions[players[pindex].pump.index]
         game.get_player(pindex).build_from_cursor{position = entry.position, direction = entry.direction}
         players[pindex].in_menu = false
         players[pindex].menu = "none"
         printout("Pump placed.", pindex)
         
      elseif players[pindex].menu == "warnings" then
         local warnings = {}
         if players[pindex].warnings.sector == 1 then
            warnings = players[pindex].warnings.short.warnings
         elseif players[pindex].warnings.sector == 2 then
            warnings = players[pindex].warnings.medium.warnings
         elseif players[pindex].warnings.sector == 3 then
            warnings= players[pindex].warnings.long.warnings
         end
         if players[pindex].warnings.category <= #warnings and players[pindex].warnings.index <= #warnings[players[pindex].warnings.category].ents then
            local ent = warnings[players[pindex].warnings.category].ents[players[pindex].warnings.index]
            if ent ~= nil and ent.valid then
               players[pindex].cursor = true
               players[pindex].cursor_pos = center_of_tile(ent.position)
               cursor_highlight(pindex, ent, nil)
               sync_build_arrow(pindex)
               printout({"access.teleported-the-cursor-to", "".. math.floor(players[pindex].cursor_pos.x) .. " " .. math.floor(players[pindex].cursor_pos.y)}, pindex)
--               players[pindex].menu = ""
--               players[pindex].in_menu = false
            else
               printout("Blank", pindex)
            end
         else
            printout("No warnings for this range.  Press tab to pick a larger range, or press E to close this menu.", pindex)
         end

      elseif players[pindex].menu == "travel" then
         if #global.players[pindex].travel == 0 and players[pindex].travel.index.x < 4 then
            printout("Move towards the right and select Create to get started.", pindex)
         elseif players[pindex].travel.index.y == 0 and players[pindex].travel.index.x < 4 then
            printout("Navigate up and down to select a fast travel point, then press left bracket to get there quickly.", pindex)
         elseif players[pindex].travel.index.x == 1 then
            local success = teleport_to_closest(pindex, global.players[pindex].travel[players[pindex].travel.index.y].position, false, false)
            if success and players[pindex].cursor then
               players[pindex].cursor_pos = table.deepcopy(global.players[pindex].travel[players[pindex].travel.index.y].position)
            else
               players[pindex].cursor_pos = offset_position(players[pindex].position, players[pindex].player_direction, 1)
            end
            sync_build_arrow(pindex)
            game.get_player(pindex).opened = nil
            cursor_highlight(pindex, nil, nil)--laterdo check for ent here for cursor highlight?
            if not refresh_player_tile(pindex) then
               printout("Tile out of range", pindex)
               return
            end
            target(pindex)

         elseif players[pindex].travel.index.x == 2 then
            printout("Enter a new name for this fast travel point, then press enter to confirm.", pindex)
            players[pindex].travel.renaming = true
            local frame = game.get_player(pindex).gui.screen["travel"]
            local input = frame.add{type="textfield", name = "input"}
            input.focus()
            input.select(1, 0)
         elseif players[pindex].travel.index.x == 3 then
            printout("Deleted " .. global.players[pindex].travel[players[pindex].travel.index.y].name, pindex)
            table.remove(global.players[pindex].travel, players[pindex].travel.index.y)
            players[pindex].travel.x = 1
            players[pindex].travel.index.y = players[pindex].travel.index.y - 1
         elseif players[pindex].travel.index.x == 4 then
            printout("Enter a name for this fast travel point, then press enter to confirm.", pindex)
            players[pindex].travel.creating = true
            local frame = game.get_player(pindex).gui.screen["travel"]
            local input = frame.add{type="textfield", name = "input"}
            input.focus()
            input.select(1, 0)
         end
         
      elseif players[pindex].menu == "structure-travel" then--Also called "b stride"
         local tar = nil
         local network = players[pindex].structure_travel.network
         local index = players[pindex].structure_travel.index
         local current = players[pindex].structure_travel.current
         if players[pindex].structure_travel.direction == "none" then
            tar = network[current]
         elseif players[pindex].structure_travel.direction == "north" then
            tar = network[network[current].north[index].num]
         elseif players[pindex].structure_travel.direction == "east" then
            tar = network[network[current].east[index].num]
         elseif players[pindex].structure_travel.direction == "south" then
            tar = network[network[current].south[index].num]
         elseif players[pindex].structure_travel.direction == "west" then
            tar = network[network[current].west[index].num]
         end   
         local success = teleport_to_closest(pindex, tar.position, false, false)
         if success and players[pindex].cursor then
            players[pindex].cursor_pos = table.deepcopy(tar.position)
         else
            players[pindex].cursor_pos = offset_position(players[pindex].position, players[pindex].player_direction, 1)
         end
         sync_build_arrow(pindex)
         game.get_player(pindex).opened = nil
         cursor_highlight(pindex, nil, nil)--laterdo check for ent here for cursor highlight?
         if not refresh_player_tile(pindex) then
            printout("Tile out of range", pindex)
            return
         end
         target(pindex)
      
      elseif players[pindex].menu == "rail_builder" then
         rail_builder(pindex, true)
         rail_builder_close(pindex,false)
      elseif players[pindex].menu == "train_menu" then
         train_menu(players[pindex].train_menu.index, pindex, true)
      elseif players[pindex].menu == "train_stop_menu" then
         train_stop_menu(players[pindex].train_stop_menu.index, pindex, true)
      elseif players[pindex].menu == "roboport_menu" then
         roboport_menu(players[pindex].roboport_menu.index, pindex, true)
      end      
   end
end)

--Left click actions with items in hand
script.on_event("click-hand", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].last_click_tick == event.tick then
      return
   end
   if players[pindex].in_menu then
      return
   else
      --Not in a menu
      local stack = game.get_player(pindex).cursor_stack
      local ent = get_selected_ent(pindex)

      if stack and stack.valid_for_read and stack.valid then
         players[pindex].last_click_tick = event.tick
      else
         return
      end
      
      --If something is in hand...     
      if stack.prototype ~= nil and (stack.prototype.place_result ~= nil or stack.prototype.place_as_tile_result ~= nil) and stack.name ~= "offshore-pump" then
         --If holding a preview of a building/tile, try to place it here
         local offset = 0
         build_item_in_hand(pindex, offset)
      elseif stack.name == "offshore-pump" then
         --If holding an offshore pump, open the offshore pump builder
         build_offshore_pump_in_hand(pindex)
      elseif stack.is_repair_tool then
         --If holding a repair pack, try to use it (will not work on enemies)
         repair_pack_used(ent,pindex)
      elseif stack.prototype ~= nil and (stack.prototype.name == "capsule" or stack.prototype.type == "capsule") then
         --If holding a capsule type, e.g. cliff explosives or robot capsules, or remotes, try to use it at the cursor position (no feedback about successful usage)
         local range = 20
         if stack.name == "cliff-explosives" then
            range = 10
         elseif stack.name == "grenade" then
            range = 15
         end
         if util.distance(game.get_player(pindex).position,players[pindex].cursor_pos) < range then
            game.get_player(pindex).use_from_cursor(players[pindex].cursor_pos)
         else
            game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            printout("Target is out of range",pindex)
         end
      elseif ent ~= nil then
         --If holding an item with no special left click actions, allow entity left click actions.
         clicked_on_entity(ent,pindex)
      else
         printout("No actions for " .. stack.name .. " in hand",pindex)
      end
   end
end)

--Left click actions with no menu and no items in hand
script.on_event("click-entity", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].last_click_tick == event.tick then
      return
   end
   if players[pindex].in_menu then
      return
   else
      --Not in a menu
      local stack = game.get_player(pindex).cursor_stack
      local ent = get_selected_ent(pindex)
      
      if stack and stack.valid_for_read and stack.valid then
         return 
      else
         players[pindex].last_click_tick = event.tick
      end
      
      --If the hand is empty...
      clicked_on_entity(ent,pindex)
   end
end)

function clicked_on_entity(ent,pindex)
   if game.get_player(pindex).vehicle ~= nil and game.get_player(pindex).vehicle.train ~= nil then
      --If player is on a train, open it
      train_menu_open(pindex)
   elseif ent == nil then
      --No entity clicked 
      return 
   elseif not ent.valid then
      --Invalid entity clicked
      game.get_player(pindex).print("Invalid entity clicked",{volume_modifier=0})
   elseif ent.train ~= nil then
      --For a rail vehicle, open train menu
      train_menu_open(pindex)
   elseif ent.name == "train-stop" then
      --For a train stop, open train stop menu
      train_stop_menu_open(pindex)
   elseif ent.name == "roboport" then
      --For a roboport, open roboport menu 
      roboport_menu_open(pindex)
   elseif ent.operable and ent.prototype.is_building then
      --If checking an operable building, open its menu
      open_operable_building(ent,pindex)
   elseif ent.operable then
      printout("No menu for " .. ent.name,pindex)
   else
      printout("No menu for " .. ent.name,pindex)
   end
end

script.on_event("repair-area", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].last_click_tick == event.tick then
      return
   end
   if players[pindex].in_menu then
      return
   else
      --Not in a menu
      local stack = game.get_player(pindex).cursor_stack
      local ent = get_selected_ent(pindex)

      if stack and stack.valid_for_read and stack.valid then
         players[pindex].last_click_tick = event.tick
      else
         return
      end
      
      --If something is in hand...     
      if stack.is_repair_tool then
         --If holding a repair pack
         repair_area(math.ceil(game.get_player(pindex).reach_distance),pindex)
      end
   end
end)

function open_operable_building(ent,pindex)--open_building
   if ent.operable and ent.prototype.is_building then
      --Check if within reach
      if util.distance(game.get_player(pindex).position, ent.position) > game.get_player(pindex).reach_distance then
         game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         printout("Building is out of player reach",pindex)
         return
      end
      --Open GUI if not already
      local p = game.get_player(pindex)
      if p.opened == nil then 
         p.opened = ent
      end
      --Other stuff...
      if ent.prototype.subgroup.name == "belt" then
         players[pindex].in_menu = true
         players[pindex].menu = "belt"
         players[pindex].move_queue = {}
         players[pindex].belt.line1 = ent.get_transport_line(1)
         players[pindex].belt.line2 = ent.get_transport_line(2)
         players[pindex].belt.ent = ent
         players[pindex].belt.sector = 1
         players[pindex].belt.network = {}
         local network = get_connected_lines(ent)
         players[pindex].belt.network = get_line_items(network)
         players[pindex].belt.index = 1
         players[pindex].belt.side = 1
         players[pindex].belt.direction = ent.direction 
         printout("Analyzing transport belt", pindex)
         --printout("Analyzing transport belt " .. #players[pindex].belt.line1 .. " " .. #players[pindex].belt.line2 .. " " .. players[pindex].belt.ent.get_max_transport_line_index(), pindex)
         return
      end
      if ent.prototype.ingredient_count ~= nil then
         players[pindex].building.recipe = ent.get_recipe()
         players[pindex].building.recipe_list = get_recipes(pindex, ent)
         players[pindex].building.category = 1
      else
         players[pindex].building.recipe = nil
         players[pindex].building.recipe_list = nil
         players[pindex].building.category = 0
      end
      players[pindex].building.item_selection = false
      players[pindex].inventory.lua_inventory = game.get_player(pindex).get_main_inventory()
      players[pindex].inventory.max = #players[pindex].inventory.lua_inventory
      players[pindex].building.sectors = {}
      players[pindex].building.sector = 1
      if ent.get_output_inventory() ~= nil then
         table.insert(players[pindex].building.sectors, {
            name = "Output",
            inventory = ent.get_output_inventory()})
      end
      if ent.get_fuel_inventory() ~= nil then
         table.insert(players[pindex].building.sectors, {
            name = "Fuel",
            inventory = ent.get_fuel_inventory()})
      end
      if ent.prototype.ingredient_count ~= nil then
         table.insert(players[pindex].building.sectors, {
            name = "Input",
            inventory = ent.get_inventory(defines.inventory.assembling_machine_input)})
      end
      if ent.get_module_inventory() ~= nil and #ent.get_module_inventory() > 0 then
         table.insert(players[pindex].building.sectors, {
            name = "Modules",
            inventory = ent.get_module_inventory()})
                  end
      if ent.get_burnt_result_inventory() ~= nil and #ent.get_burnt_result_inventory() > 0 then
         table.insert(players[pindex].building.sectors, {
            name = "Burned",
            inventory = ent.get_burnt_result_inventory()})
      end
      if ent.fluidbox ~= nil and #ent.fluidbox > 0 then
         table.insert(players[pindex].building.sectors, {
            name = "Fluid",
            inventory = ent.fluidbox})
      end

      if ent.filter_slot_count > 0 and ent.type == "inserter" then
         table.insert(players[pindex].building.sectors, {
            name = "Filters",
            inventory = {}})
         for i = 1, ent.filter_slot_count do
            local filter = ent.get_filter(i)
            if filter == nil then
               filter = "No filter selected."
            end
            table.insert(players[pindex].building.sectors[#players[pindex].building.sectors].inventory, filter)
         end
         table.insert(players[pindex].building.sectors[#players[pindex].building.sectors].inventory, ent.inserter_filter_mode)
         players[pindex].item_selection = false
         players[pindex].item_cache = {}
         players[pindex].item_selector = {
            index = 0,
            group = 0,
            subgroup = 0
         }
      end

      for i1=#players[pindex].building.sectors, 2, -1 do
         for i2 = i1-1, 1, -1 do
            if players[pindex].building.sectors[i1].inventory == players[pindex].building.sectors[i2].inventory then
               table.remove(players[pindex].building.sectors, i2)
               i2 = i2 + 1
            end
         end
      end
      if #players[pindex].building.sectors > 0 then
         players[pindex].building.ent = ent
         players[pindex].in_menu = true
         players[pindex].menu = "building"
         players[pindex].move_queue = {}
         players[pindex].inventory.index = 1
         players[pindex].building.index = 1
         
         --For assembling machine types with no recipe, open recipe building sector directly
         local recipe = players[pindex].building.recipe
         if (recipe == nil or not recipe.valid) and (ent.prototype.type == "assembling-machine") and players[pindex].building.recipe_list ~= nil then
            players[pindex].building.sector = #players[pindex].building.sectors + 1
            players[pindex].building.index = 1
            players[pindex].building.category = 1
            players[pindex].building.recipe_selection = false

            players[pindex].building.item_selection = false
            players[pindex].item_selection = false
            players[pindex].item_cache = {}
            players[pindex].item_selector = {
               index = 0,
               group = 0,
               subgroup = 0
            }
            read_building_recipe(pindex, "Select a Recipe, ")
            return
         end
         read_building_slot(pindex, true)
      else
         if game.get_player(pindex).opened ~= nil then
            printout(ent.name .. ", this menu has no options ", pindex)
         else
            printout(ent.name .. " has no menu ", pindex)
         end
      end
   else
      printout("Not an operable building.", pindex)
   end
end

--[[Attempts to build the item in hand.
* Does nothing if the hand is empty or the item is not a place-able entity.
* If the item is an offshore pump, calls a different, special function for it.
* You can offset the building with respect to the direction the player is facing. The offset is multiplied by the placed building width.
]]
function build_item_in_hand(pindex, offset_val)
   local stack = game.get_player(pindex).cursor_stack
   local offset = offset_val or 0
   
   if not (stack and stack.valid and stack.valid_for_read) then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
      local message =  "Invalid item in hand!"
	  if game.get_player(pindex).is_cursor_empty() then
	     local auto_cancel_when_empty = true --laterdo this check may become a toggle-able game setting
	     if players[pindex].build_lock == true and auto_cancel_when_empty then 
		    players[pindex].build_lock = false
		    message = "Build lock disabled, empty hand."
	     end
	  end
	  printout(message,pindex)
      return
   end
   
   if stack.name == "offshore-pump" then
      build_offshore_pump_in_hand(pindex)
      return
   elseif stack.name == "rail" then 
      if offset_val ~= 1.337 then --only when sentinel value, it allows free building rails
         local pos = players[pindex].cursor_pos
         append_rail(pos, pindex)
         return
      end
   elseif stack.name == "rail-signal" or stack.name == "rail-chain-signal" then
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
	  printout("You need to use the building menu of a rail.",pindex)
      return
   end
   
   if stack and stack.valid_for_read and stack.valid and stack.prototype.place_result ~= nil then
      local ent = stack.prototype.place_result
      local dimensions = get_tile_dimensions(stack.prototype, players[pindex].building_direction * dirs.east)
      local position = nil

      if not(players[pindex].cursor) then
         local old_pos = game.get_player(pindex).position
         local adjusted_offset = offset
         if stack.name == "locomotive" or stack.name == "cargo-wagon" or stack.name == "fluid-wagon" or stack.name == "artillery-wagon" then
            --Allow easy placement onto rails.
            adjusted_offset = 2.5
            position = offset_position(old_pos, players[pindex].player_direction, adjusted_offset)
         else
            local width = stack.prototype.place_result.tile_width
            local height = stack.prototype.place_result.tile_height
            local left_top = {x = math.floor(players[pindex].cursor_pos.x),y = math.floor(players[pindex].cursor_pos.y)}
            local right_bottom = {x = left_top.x + width, y = left_top.y + height}
            local flip = false
            local dir = players[pindex].building_direction * dirs.east
            local p_dir = players[pindex].player_direction
            
            if dir == dirs.east or dir == dirs.west then--Note, does not cover diagonal directions for non-square objects.
               flip = true
            end

            if p_dir == dirs.west and not flip then
               left_top.x = (left_top.x - width + 1)
               right_bottom.x = (right_bottom.x - width + 1)
            elseif p_dir == dirs.west and flip then
               left_top.x = (left_top.x - height + 1)
               right_bottom.x = (right_bottom.x - height + 1)
            elseif p_dir == dirs.north and not flip then
               left_top.y = (left_top.y - height + 1)
               right_bottom.y = (right_bottom.y - height + 1)
            elseif p_dir == dirs.north and flip then
               left_top.y = (left_top.y - width + 1)
               right_bottom.y = (right_bottom.y - width + 1)
            end

            position = {x = left_top.x + math.floor(width/2),y = left_top.y + math.floor(height/2)}
            if flip then
               position = {x = left_top.x + math.floor(height/2),y = left_top.y + math.floor(width/2)}
            end
            
            --Apply extra offsets if Any
            position = offset_position(position, players[pindex].player_direction, adjusted_offset)
         end
         
      else
         --Cursor offset
         local old_pos = players[pindex].cursor_pos
         local adjusted_position = offset_position(old_pos, dirs.south, dimensions.y/2 - .5 )
         local adjusted_position = offset_position(adjusted_position, dirs.east, dimensions.x/2 - .5 )
         local adjusted_offset = offset
         position = offset_position(adjusted_position, players[pindex].player_direction, adjusted_offset)
      end
      if stack.name == "small-electric-pole" and players[pindex].build_lock == true then
         --Place a small electric pole in this position only if it is within 6.5 to 7.5 tiles of another small electric pole
         local surf = game.get_player(pindex).surface
         local small_poles = surf.find_entities_filtered{position = position, radius = 7.5, name = "small-electric-pole"}
         local all_beyond_6_5 = true
         local any_connects = false
         local any_found = false
         for i,pole in ipairs(small_poles) do
            any_found = true
            if util.distance(position, pole.position) < 6.5 then
               all_beyond_6_5 = false
            elseif util.distance(position, pole.position) >= 6.5 then
               any_connects = true
            end
         end
         if not (all_beyond_6_5 and any_connects) then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            if not any_found then
               game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            end
            return
         end
	  elseif stack.name == "medium-electric-pole" and players[pindex].build_lock == true then
         --Place a medium electric pole in this position only if it is within 6.5 to 7.5 tiles of another medium electric pole
         local surf = game.get_player(pindex).surface
         local med_poles = surf.find_entities_filtered{position = position, radius = 7.5, name = "medium-electric-pole"}
         local all_beyond_6_5 = true
         local any_connects = false
         local any_found = false
         for i,pole in ipairs(med_poles) do
            any_found = true
            if util.distance(position, pole.position) < 6.5 then
               all_beyond_6_5 = false
            elseif util.distance(position, pole.position) >= 6.5 then
               any_connects = true
            end
         end
         if not (all_beyond_6_5 and any_connects) then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            if not any_found then
               game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            end
            return
         end 
      elseif stack.name == "big-electric-pole" and players[pindex].build_lock == true then
         --Place a big electric pole in this position only if it is within 29 to 30 tiles of another medium electric pole
         position = offset_position(position, players[pindex].player_direction, -1)
         local surf = game.get_player(pindex).surface
         local big_poles = surf.find_entities_filtered{position = position, radius = 30, name = "big-electric-pole"}
         local all_beyond_min = true
         local any_connects = false
         local any_found = false
         for i,pole in ipairs(big_poles) do
            any_found = true
            if util.distance(position, pole.position) < 28.5 then
               all_beyond_min = false
            elseif util.distance(position, pole.position) >= 28.5 then
               any_connects = true
            end
         end
         if not (all_beyond_min and any_connects) then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            if not any_found then
               game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            end
            return
         end 
       elseif stack.name == "substation" and players[pindex].build_lock == true then
         --Place a substation in this position only if it is within 16 to 18 tiles of another medium electric pole
         position = offset_position(position, players[pindex].player_direction, -1)
         local surf = game.get_player(pindex).surface
         local sub_poles = surf.find_entities_filtered{position = position, radius = 18.01, name = "substation"}
         local all_beyond_min = true
         local any_connects = false
         local any_found = false
         for i,pole in ipairs(sub_poles) do
            any_found = true
            if util.distance(position, pole.position) < 17.01 then
               all_beyond_min = false
            elseif util.distance(position, pole.position) >= 17.01 then
               any_connects = true
            end
         end
         if not (all_beyond_min and any_connects) then
            game.get_player(pindex).play_sound{path = "Inventory-Move"}
            if not any_found then
               game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            end
            return
         end 
	  end
	  --Build it
     if players[pindex].cursor then--In cursor mode, build where the cursor is points.
        position = position
     end
      local building = {
         position = position,
         direction = players[pindex].building_direction * dirs.east,
         alt = false
      }
      --building.position = game.get_player(pindex).surface.find_non_colliding_position(ent.name, position, .5, .05)--DOES NOT RESPECT DIRECTION
      if building.position ~= nil and game.get_player(pindex).can_build_from_cursor(building) then 
         game.get_player(pindex).build_from_cursor(building)  
--         read_tile(pindex)
      else
         if players[pindex].build_lock == true then
            game.get_player(pindex).play_sound{path = "utility/cannot_build"}
         else
            game.get_player(pindex).play_sound{path = "utility/cannot_build"}
            printout("Cannot place that there.", pindex)
         end
      end
   elseif stack and stack.valid_for_read and stack.valid and stack.prototype.place_as_tile_result ~= nil then
      --Place paving tiles 
	  local p = game.get_player(pindex)
	  local t_size = players[pindex].cursor_size * 2 + 1
     local pos = players[pindex].cursor_pos--Center on the cursor in default
     if players[pindex].cursor and players[pindex].preferences.tiles_placed_from_northwest_corner then
        pos.x = pos.x - players[pindex].cursor_size
        pos.y = pos.y - players[pindex].cursor_size
     end
	  if p.can_build_from_cursor{position = pos, terrain_building_size = t_size} then
	     p.build_from_cursor{position = pos, terrain_building_size = t_size}
	  else
	     p.play_sound{path = "utility/cannot_build"}
	  end 
   else
      game.get_player(pindex).play_sound{path = "utility/cannot_build"}
   end
end

--[[Assisted building function for offshore pumps.
* Called as a special case by build_item_in_hand
]]
function build_offshore_pump_in_hand(pindex)
   local stack = game.get_player(pindex).cursor_stack

   if stack and stack.valid and stack.valid_for_read and stack.name == "offshore-pump" then
      local ent = stack.prototype.place_result
      players[pindex].pump.positions = {}
      local initial_position = game.get_player(pindex).position
      initial_position.x = math.floor(initial_position.x) 
      initial_position.y = math.floor(initial_position.y)
      for i1 = -10, 10 do
         for i2 = -10, 10 do
            for i3 = 0, 3 do
            local position = {x = initial_position.x + i1, y = initial_position.y + i2}
               if game.get_player(pindex).can_build_from_cursor{name = "offshore-pump", position = position, direction = i3 * 2} then
                  table.insert(players[pindex].pump.positions, {position = position, direction = i3*2})
               end
            end
         end
      end
      if #players[pindex].pump.positions == 0 then
         printout("No available positions.  Try moving closer to water.", pindex)
      else
         players[pindex].in_menu = true
         players[pindex].menu = "pump"
         players[pindex].move_queue = {}
         printout("There are " .. #players[pindex].pump.positions .. " possibilities, scroll up and down, then select one to build, or press e to cancel.", pindex)
         table.sort(players[pindex].pump.positions, function(k1, k2) 
            return distance(initial_position, k1.position) < distance(initial_position, k2.position)
         end)

         players[pindex].pump.index = 0
      end
   end
end


script.on_event("crafting-all", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu then
      if players[pindex].menu == "crafting" then
         local recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index]
         local T = {
            count = game.get_player(pindex).get_craftable_count(recipe),
         recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index],
            silent = false
         }
         local count = game.get_player(pindex).begin_crafting(T)
         if count > 0 then
            printout("Started crafting " .. count .. " " .. T.recipe.name, pindex)
         else
            printout("Not enough materials", pindex)
         end

      elseif players[pindex].menu == "crafting_queue" then
         load_crafting_queue(pindex)
         if players[pindex].crafting_queue.max >= 1 then
            local T = {
            index = players[pindex].crafting_queue.index,
               count = players[pindex].crafting_queue.lua_queue[players[pindex].crafting_queue.index].count
            }
            game.get_player(pindex).cancel_crafting(T)
            load_crafting_queue(pindex)
            read_crafting_queue(pindex)

         end
      end
   end
end)


script.on_event("transfer-one-stack", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu then
      if players[pindex].menu == "building" then
         if players[pindex].building.sector <= #players[pindex].building.sectors and #players[pindex].building.sectors[players[pindex].building.sector].inventory > 0 and players[pindex].building.sectors[players[pindex].building.sector].name ~= "Fluid" then
            --Transfer stack from building to player inventory
			local stack = players[pindex].building.sectors[players[pindex].building.sector].inventory[players[pindex].building.index]
            if stack and stack.valid and stack.valid_for_read then
               if game.get_player(pindex).can_insert(stack) then
                  game.get_player(pindex).play_sound{path = "utility/inventory_move"}
                  local result = stack.name
                  local inserted = game.get_player(pindex).insert(stack)
                  players[pindex].building.sectors[players[pindex].building.sector].inventory.remove{name = stack.name, count = inserted}
                  result = "Moved " .. inserted .. " " .. result .. " to player's inventory."--**laterdo note that ammo gets inserted to ammo slots first
                  printout(result, pindex)
               else
                  local result = "Cannot insert " .. stack.name .. " to player's inventory, "
				  if game.get_player(pindex).get_main_inventory().count_empty_stacks() == 0 then
				     result = result .. "because it is full."
				  end
				  printout(result,pindex)
               end
            end
         else
            local offset = 1
            if players[pindex].building.recipe_list ~= nil then
               offset = offset + 1
            end
            if players[pindex].building.sector == #players[pindex].building.sectors + offset then
		       --Transfer stack from player inventory to building
               local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
               if stack and stack.valid and stack.valid_for_read then
                  if players[pindex].building.ent.can_insert(stack) then
                     game.get_player(pindex).play_sound{path = "utility/inventory_move"}
                     local result = stack.name
                     local inserted = players[pindex].building.ent.insert(stack)
                     players[pindex].inventory.lua_inventory.remove{name = stack.name, count = inserted}
                     result = "Moved " .. inserted .. " " .. result .. " to " .. players[pindex].building.ent.name
                     printout(result, pindex)
                  else
					 local result = "Cannot insert " .. stack.name .. " to " .. players[pindex].building.ent.name
				     printout(result,pindex)
                  end
               end
            end
         end
      end
   end
end)

--You can equip armor, armor equipment, guns, ammo. You can equip from the hand, or from the inventory with an empty hand.
script.on_event("equip-item", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local stack = game.get_player(pindex).cursor_stack
   local result = ""
   if stack ~= nil and stack.valid_for_read and stack.valid then
      --Equip item grabbed in hand, for selected menus
      if not players[pindex].in_menu or players[pindex].menu == "inventory" then
         result = equip_it(stack,pindex)
      end
   elseif players[pindex].menu == "inventory" then
      --Equip the selected item from its inventory slot directly
      local stack = game.get_player(pindex).get_main_inventory()[players[pindex].inventory.index]
      result = equip_it(stack,pindex)
      
   elseif players[pindex].menu == "building" then
      --Something will be smart-inserted so do nothing here
      return
   end
   
   if result ~= "" then
      --game.get_player(pindex).print(result)--**
      printout(result,pindex)
   end
end)

script.on_event("open-rail-builder", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu then
      return
   else
      --Not in a menu
      local ent =  get_selected_ent(pindex)
      if ent then 
         if ent.name == "straight-rail" then
            --Open rail builder
            rail_builder_open(pindex, ent)
         elseif ent.name == "curved-rail" then
            printout("Rail builder menu cannot use curved rails.", pindex)
         end
      end
   end
end)

script.on_event("quick-build-rail-left-turn", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   if not ent then
      return
   end
   --Build left turns on end rails
   if ent.name == "straight-rail" then
      build_rail_turn_left_45_degrees(ent, pindex)
   end
end)

script.on_event("quick-build-rail-right-turn", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   if not ent then
      return
   end
   --Build left turns on end rails
   if ent.name == "straight-rail" then
      build_rail_turn_right_45_degrees(ent, pindex)
   end
end)

--[[Imitates vanilla behavior: 
* Control click an item in an inventory to try smart transfer ALL of it. 
* Control click an empty slot to try to smart transfer ALL items from that inventory.
]]
script.on_event("transfer-all-stacks", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end

   if players[pindex].in_menu then
      if players[pindex].menu == "building" then
         do_multi_stack_transfer(1,pindex)
      end
   end
end)

--Default is control clicking
script.on_event("free-place-straight-rail", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end

   if players[pindex].in_menu then
      return
   else
      --Not in a menu
      local stack = game.get_player(pindex).cursor_stack
      local ent =  get_selected_ent(pindex)
      if stack and stack.valid_for_read and stack.valid and stack.name == "rail" then
         --Straight rail free placement
         build_item_in_hand(pindex, 1.337)--Uses sentinel value
      end
   end
end)

--[[Imitates vanilla behavior: 
* Control click an item in an inventory to try smart transfer HALF of it. 
* Control click an empty slot to try to smart transfer HALF of all items from that inventory.
]]
script.on_event("transfer-half-of-all-stacks", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end

   if players[pindex].in_menu then
      if players[pindex].menu == "building" then
         do_multi_stack_transfer(0.5,pindex)
      end
   end
end)

--[[Manages inventory transfers that are bigger than one stack. 
* Has checks and printouts!
]]
function do_multi_stack_transfer(ratio,pindex)
   local result = {""}
   local sector = players[pindex].building.sectors[players[pindex].building.sector]
   if sector and #sector.inventory > 0 and sector.name ~= "Fluid" then
      --This is the section where we move from the building to the player.
      local item_name=""
      local stack = sector.inventory[players[pindex].building.index]
      if stack and stack.valid and stack.valid_for_read then
         item_name = stack.name
      end
      
      local moved, full = transfer_inventory{from=sector.inventory,to=game.players[pindex],name=item_name,ratio=ratio}
      if full then
         table.insert(result,{"inventory-full-message.main"})
         table.insert(result,", ")
      end
      if table_size(moved) == 0 then
         table.insert(result,{"access.grabbed-nothing"})
      else
         game.get_player(pindex).play_sound{path = "utility/inventory_move"}
         local item_list={""}
         for name, amount in pairs(moved) do
            table.insert(item_list,{"access.item-quantity",game.item_prototypes[name].localised_name,amount})
            table.insert(item_list,", ")
         end
         --trim traling comma off
         item_list[#item_list]=nil
         table.insert(result,{"access.grabbed-stuff",item_list})
      end
      
   else
      local offset = 1
      if players[pindex].building.recipe_list ~= nil then
         offset = offset + 1
      end
      if players[pindex].building.sector == #players[pindex].building.sectors + offset then
         --This is the section where we move from the player to the building.
         local item_name=""
         local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
         if stack and stack.valid and stack.valid_for_read then
            item_name = stack.name
         end
         
         local moved, full = transfer_inventory{from=game.players[pindex].get_main_inventory(),to=players[pindex].building.ent,name=item_name,ratio=ratio}
         
         if full then
            table.insert(result,"Inventory full or not applicable, ")
         end
         if table_size(moved) == 0 then
            table.insert(result,{"access.placed-nothing"})
         else
            game.get_player(pindex).play_sound{path = "utility/inventory_move"}
            local item_list={""}
            for name, amount in pairs(moved) do
               table.insert(item_list,{"access.item-quantity",game.item_prototypes[name].localised_name,amount})
               table.insert(item_list,", ")
            end
            --trim traling comma off
            item_list[#item_list]=nil
            table.insert(result,{"access.placed-stuff",breakup_string(item_list)})
         end
      end
   end
   printout(result, pindex)
end

--[[Transfers multiple stacks of a specific item (or all items) to/from the player inventory from/to a building inventory.
* item name / empty string to indicate transfering everything
* ratio (between 0 and 1), the ratio of the total count to transder for each item.
* Has no checks or printouts!
]]
function transfer_inventory(args)
   args.name = args.name or ""
   args.ratio = args.ratio or 1
   local transfer_list={}
   if args.name ~= "" then
      transfer_list[args.name] = args.from.get_item_count(args.name)
   else
      transfer_list = args.from.get_contents()
   end
   local full=false
   res = {}
   for name, amount in pairs(transfer_list) do
      amount = math.ceil(amount * args.ratio)
      local actual_amount = args.to.insert({name=name, count=amount})
      if actual_amount ~= amount then
         print(name,amount,actual_amount)
         amount = actual_amount
         full = true
      end
      if amount > 0 then
         res[name] = amount
         args.from.remove({name=name, count=amount})
      end
   end
   return res, full
end

script.on_event("crafting-5", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   local stack = game.get_player(pindex).cursor_stack
   if players[pindex].in_menu then
      if players[pindex].menu == "crafting" then
         local recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index]
         local T = {
            count = 5,
         recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index],
            silent = false
         }
         local count = game.get_player(pindex).begin_crafting(T)
         if count > 0 then
            printout("Started crafting " .. count .. " " .. T.recipe.name, pindex)
         else
            printout("Not enough materials", pindex)
         end

      elseif players[pindex].menu == "crafting_queue" then
         load_crafting_queue(pindex)
         if players[pindex].crafting_queue.max >= 1 then
            local T = {
            index = players[pindex].crafting_queue.index,
               count = 5
            }
            game.get_player(pindex).cancel_crafting(T)
            load_crafting_queue(pindex)
            read_crafting_queue(pindex)
         end
      end
   end
end)

script.on_event("menu-clear-filter", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   local stack = game.get_player(pindex).cursor_stack
   if players[pindex].in_menu then
      if players[pindex].menu == "building" then
         local stack = game.get_player(pindex).cursor_stack
         if players[pindex].building.sector <= #players[pindex].building.sectors then
            if stack and stack.valid_for_read and stack.valid and stack.count > 0 then
               local iName = players[pindex].building.sectors[players[pindex].building.sector].name
               if iName ~= "Fluid" and iName ~= "Filters" then
                  T = {
                     name = stack.name,
                     count = 1
                  }                  
                  local building = players[pindex].building
                  local target_stack = building.sectors[building.sector].inventory[building.index]

                  if target_stack and target_stack.transfer_stack{name=stack.name} then
                      printout("Inserted 1 " .. stack.name, pindex)
                     stack.count = stack.count - 1
                  else
                     printout("Cannot insert " .. stack.name .. " into " .. players[pindex].building.sectors[players[pindex].building.sector].name, pindex)
                  end
               
               elseif iName == "Filters" and players[pindex].item_selection == false and players[pindex].building.index < #players[pindex].building.sectors[players[pindex].building.sector].inventory then 
                  players[pindex].building.ent.set_filter(players[pindex].building.index, nil)
                  players[pindex].building.sectors[players[pindex].building.sector].inventory[players[pindex].building.index] = "No filter selected."
                  printout("Filter cleared", pindex)

               end
            elseif players[pindex].building.sectors[players[pindex].building.sector].name == "Filters" and players[pindex].building.item_selection == false and players[pindex].building.index < #players[pindex].building.sectors[players[pindex].building.sector].inventory then
               players[pindex].building.ent.set_filter(players[pindex].building.index, nil)
               players[pindex].building.sectors[players[pindex].building.sector].inventory[players[pindex].building.index] = "No filter selected."
               printout("Filter cleared.", pindex)
            end
         end
      end
   end
end)

--Reads the entity status but also adds on extra info depending on the entity
script.on_event("read-entity-status", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   local stack = game.get_player(pindex).cursor_stack
   if players[pindex].in_menu then
      return
   elseif ent then
      --Print out the status of a machine, if it exists.
      local result = ""
      local ent_status_id = ent.status
      local ent_status_text = ""
      local status_lookup = into_lookup(defines.entity_status)
      if ent.name == "cargo-wagon" then
         --Instead of status, read contents   
         result = " " .. cargo_wagon_top_contents_info(ent)
      elseif ent.name == "fluid-wagon" then
         --Instead of status, read contents   
         result =  " " .. fluid_contents_info(ent)
      elseif ent_status_id ~= nil then
         --Print status if it exists
         ent_status_text = status_lookup[ent_status_id]
         result =  " " .. ent_status_text
      else--There is no status
	      --When there is no status, for entities with fuel inventories, read that out instead. This is typical for vehicles.
	      if ent.get_fuel_inventory() ~= nil then
		      result = " " .. fuel_inventory_info(ent)
		   elseif ent.type == "electric-pole" then
		    --For electric poles with no power flow, report the nearest electric pole with a power flow.
            if get_electricity_satisfaction(ent) > 0 then
               result = get_electricity_satisfaction(ent) .. " percent network satisfaction, with " .. get_electricity_flow_info(ent)
            else
               result = "No power, " .. report_nearest_supplied_electric_pole(ent)
            end
         else
            result = "No status."
         end
      end
      --For working or normal entities, give some extra info about specific entities.
      if result == "" then
         result = "result error"
      end
      
      --For working or normal entities, give some extra info about specific entities in terms of speeds or bonuses.
      local list = defines.entity_status
      if ent.status ~= nil and ent.status ~= list.no_power and ent.status ~= list.no_power and ent.status ~= list.no_fuel then
         if ent.type == "inserter" then --items per minute based on rotation speed and the STATED hand capacity
            local cap = ent.force.inserter_stack_size_bonus + 1
            if ent.name == "stack-inserter" or ent.name == "stack-filter-inserter" then
               cap = ent.force.stack_inserter_capacity_bonus + 1
            end
            local rate = string.format(" %.1f ", cap * ent.prototype.inserter_rotation_speed * 57.5) 
            result = result .. ", can move " .. rate .. " items per second, with a hand capacity of " .. cap
         end
         if ent.prototype ~= nil and ent.prototype.belt_speed ~= nil and ent.prototype.belt_speed > 0 then --items per minute by simple reading
            if ent.name == "splitter" or ent.name == "fast-splitter" or ent.name == "express splitter" then
               result = result .. ", can process " .. math.floor(ent.prototype.belt_speed * 480 * 2) .. " items per second"
            else 
               result = result .. ", can move " .. math.floor(ent.prototype.belt_speed * 480) .. " items per second"
            end
         end
         if ent.type == "assembling-machine" or ent.type == "furnace" then --Crafting cycles per minute based on recipe time and the STATED craft speed ; laterdo maybe extend this to all "crafting machine" types?
            local progress = ent.crafting_progress
            local speed = ent.crafting_speed
            local recipe_time = 0
            local cycles = 0-- crafting cycles completed per minute for this recipe
            if ent.get_recipe() ~= nil and ent.get_recipe().valid then
               recipe_time = ent.get_recipe().energy
               cycles = 60 / recipe_time * speed
            end
            local cycles_string = string.format(" %.2f ", cycles)
            if cycles == math.floor(cycles) then
               cycles_string = math.floor(cycles)
            end
            local speed_string = string.format(" %.2f ", speed)
            if speed == math.floor(speed) then
               speed_string = math.floor(speed)
            end
            if cycles < 10 then --more than 6 seconds to craft
               result = result .. ", recipe progress " .. math.floor(progress * 100) .. " percent "
            end
            if cycles > 0 then
               result = result .. ", can complete " .. cycles_string .. " recipe cycles per minute "
            end
            result = result .. ", with a crafting speed of " .. speed_string .. ", at " .. math.floor(100 * (1 + ent.speed_bonus) + 0.5) .. " percent "
            if ent.productivity_bonus ~= 0 then
               result = result .. ", with productivity bonus " .. math.floor(100 * (0 + ent.productivity_bonus) + 0.5) .. " percent "
            end
         elseif ent.type == "mining-drill" then
            result = result .. ", producing " .. string.format(" %.2f ",ent.prototype.mining_speed * 60 * (1 + ent.speed_bonus)) .. " items per minute "
            if ent.speed_bonus ~= 0 then
               result = result .. ", with speed " .. math.floor(100 * (1 + ent.speed_bonus) + 0.5) .. " percent " 
            end
            if ent.productivity_bonus ~= 0 then
               result = result .. ", with productivity bonus " .. math.floor(100 * (0 + ent.productivity_bonus) + 0.5) .. " percent "
            end 
         elseif ent.name == "lab" then
            if ent.speed_bonus ~= 0 then
               result = result .. ", with speed " .. math.floor(100 * (1 + ent.force.laboratory_speed_modifier * (1 + (ent.speed_bonus - ent.force.laboratory_speed_modifier))) + 0.5) .. " percent " --laterdo fix bug**
               --game.get_player(pindex).print(result)
            end
            if ent.productivity_bonus ~= 0 then
               result = result .. ", with productivity bonus " .. math.floor(100 * (0 + ent.productivity_bonus + ent.force.laboratory_productivity_bonus) + 0.5) .. " percent "
            end
         else --All other entities with the an applicable status
            if ent.speed_bonus ~= 0 then
               result = result .. ", with speed " .. math.floor(100 * (1 + ent.speed_bonus) + 0.5) .. " percent "
            end
            if ent.productivity_bonus ~= 0 then
               result = result .. ", with productivity bonus " .. math.floor(100 * (0 + ent.productivity_bonus) + 0.5) .. " percent "
            end
         end
         --laterdo maybe pump speed?
      end
            
      --Entity power usage
      local power_rate = (1 + ent.consumption_bonus)
      local drain = ent.electric_drain
      if drain ~= nil then
         drain = drain * 60
      else
         drain = 0
      end
      local uses_energy = false
      if drain > 0 or (ent.prototype ~= nil and ent.prototype.max_energy_usage ~= nil and ent.prototype.max_energy_usage > 0) then
         uses_energy = true
      end
      if ent.status ~= nil and uses_energy and ent.status == list.working then
         result = result .. ", consuming " .. get_power_string(ent.prototype.max_energy_usage * 60 * power_rate + drain)
      elseif ent.status ~= nil and uses_energy and ent.status == list.no_power or ent.status == list.low_power then
         result = result .. ", consuming less than " .. get_power_string(ent.prototype.max_energy_usage * 60 * power_rate + drain)
      elseif ent.status ~= nil and uses_energy or (ent.prototype ~= nil and ent.prototype.max_energy_usage ~= nil and ent.prototype.max_energy_usage > 0) then
         result = result .. ", idle and consuming " .. get_power_string(drain)
      end
      if uses_energy and ent.prototype.burner_prototype ~= nil then
         result = result .. " as burner fuel "
      end
      
      --Entity Health 
      if ent.is_entity_with_health and ent.get_health_ratio() == 1 then
         result = result .. ", full health "
      elseif ent.is_entity_with_health then
         result = result .. ", " .. math.floor(ent.get_health_ratio() * 100) .. " percent health"
      end
      
      if ent.name == "straight-rail" then
         -- Report nearest rail intersection position -- laterdo find better keybind
         local nearest, dist = find_nearest_intersection(ent, pindex)
         if nearest == nil then
            result = result .. ", no rail intersections within " .. dist .. " tiles " 
         else
            result = result .. ", nearest rail intersection at " .. dist .. " " .. direction_lookup(get_direction_of_that_from_this(nearest.position,ent.position))
         end
      end
      
      printout(result ,pindex)
      --game.get_player(pindex).print(result)--**
      
   end
end)

function into_lookup(array)
    local lookup = {}
    for key, value in pairs(array) do
        lookup[value] = key
    end
    return lookup
end

script.on_event("rotate-building", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not(players[pindex].in_menu) then
      local ent = get_selected_ent(pindex)
      local stack = game.get_player(pindex).cursor_stack
      if stack and stack.valid_for_read and stack.valid and stack.prototype.place_result ~= nil then
         if stack.prototype.place_result.supports_direction then
            if not(players[pindex].building_direction_lag) then
               game.get_player(pindex).play_sound{path="Rotate-Hand-Sound"}
               players[pindex].building_direction = players[pindex].building_direction + 1
               if players[pindex].building_direction > 3 then
                  players[pindex].building_direction = players[pindex].building_direction %4
               end
            end
            if players[pindex].building_direction == 0 then
               printout("North", pindex)
            elseif players[pindex].building_direction == 1 then
               printout("East", pindex)
            elseif players[pindex].building_direction == 2 then
               printout("South", pindex)
            elseif players[pindex].building_direction == 3 then
               printout("West", pindex)
            end
            players[pindex].building_direction_lag = false
         else
            printout(stack.name .. " cannot be rotated.", pindex)
         end
      elseif ent then
         if ent.supports_direction then
            if not(players[pindex].building_direction_lag) then
               local T = {
                  reverse = false,
                  by_player = event.player_index
               }
                  if not(ent.rotate(T)) then
                     printout("Cannot rotate this object.", pindex)
                     return
                  end
            else
               players[pindex].building_direction_lag = false
            end
            if ent.direction == 0 then
               printout("North", pindex)
            elseif ent.direction == 2 then
               printout("East", pindex)
            elseif ent.direction == 4 then
               printout("South", pindex)
            elseif ent.direction == 6 then
               printout("West", pindex)
            else
               printout("Not a direction...", pindex)
            end
         else
            printout(ent.name .. " cannot be rotated.", pindex)
         end               
      else
         print("not a valid stack for rotating", pindex)
      end
   end
   sync_build_arrow(pindex)
end)

script.on_event("inventory-read-weapons-data", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not(players[pindex].in_menu) then
      return
   elseif players[pindex].menu == "inventory" then
      --Read Weapon data
	  local result = read_weapons_and_ammo(pindex)
	  --game.get_player(pindex).print(result)--
	  printout(result,pindex)
   end
end)

script.on_event("inventory-reload-weapons", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].menu == "inventory" then
      --Reload weapons
	  local result = reload_weapons(pindex)
	  --game.get_player(pindex).print(result)
	  printout(result,pindex)
   end
end)

script.on_event("inventory-remove-all-weapons-and-ammo", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].menu == "inventory" then
	  local result = remove_weapons_and_ammo(pindex)
	  --game.get_player(pindex).print(result)
	  printout(result,pindex)
   end
end)

--Reads the custom info for an item selected. If you are driving, it returns custom vehicle info
script.on_event("item-info", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if game.get_player(pindex).driving and players[pindex].menu ~= "train_menu" then
      printout(vehicle_info(pindex),pindex)
      return
   end
   local offset = 0
   if players[pindex].menu == "building" and players[pindex].building.recipe_list ~= nil then
      offset = 1
   end
   if not players[pindex].in_menu then
      local ent =  get_selected_ent(pindex)
      if ent then
         local str = ent.localised_description
         if str == nil or str == "" then
            str = "No description for this entity"
         end
         printout(str, pindex)
      else
         printout("Nothing selected, use this key to describe an entity or item that you select.", pindex)
      end
   elseif players[pindex].in_menu then
      if players[pindex].menu == "inventory" or (players[pindex].menu == "building" and players[pindex].building.sector > offset + #players[pindex].building.sectors) then
         local stack = players[pindex].inventory.lua_inventory[players[pindex].inventory.index]
         if stack and stack.valid_for_read and stack.valid == true then
            local str = ""
            if stack.prototype.place_result ~= nil then
               str = stack.prototype.place_result.localised_description
            else
               str = stack.prototype.localised_description
            end
            if str == nil or str == "" then
               str = "No description"
            end
            printout(str, pindex)
         else
            printout("No description", pindex)
         end

      elseif players[pindex].menu == "technology" then
         local techs = {}
         if players[pindex].technology.category == 1 then
            techs = players[pindex].technology.lua_researchable
         elseif players[pindex].technology.category == 2 then
            techs = players[pindex].technology.lua_locked
         elseif players[pindex].technology.category == 3 then
            techs = players[pindex].technology.lua_unlocked
         end
   
         if next(techs) ~= nil and players[pindex].technology.index > 0 and players[pindex].technology.index <= #techs then
            local result = "Unlocks the following:"
            local rewards = techs[players[pindex].technology.index].effects
            for i, reward in ipairs(rewards) do
               for i1, v in pairs(reward) do
                  if v then
                     result = result ..  tostring(v) .. " , "
                  end
               end
            end
            printout(string.sub(result, 1, -3), pindex)
         end

      elseif players[pindex].menu == "crafting" then
         local recipe = players[pindex].crafting.lua_recipes[players[pindex].crafting.category][players[pindex].crafting.index]
         if recipe ~= nil and #recipe.products > 0 then
            local product_name = recipe.products[1].name
            local product = game.item_prototypes[product_name]
                     local str = ""
                  if product.place_result ~= nil then
                     str = product.place_result.localised_description
                  else
                     str = product.localised_description
                  end
                  if str == nil or str == "" then
                     str = "No description found for this item"
                  end
                  printout(str, pindex)
         else
            printout("No description found, menu error", pindex)
         end
      elseif players[pindex].menu == "building" then 
         if players[pindex].building.recipe_selection then
            local recipe = players[pindex].building.recipe_list[players[pindex].building.category][players[pindex].building.index]
            if recipe ~= nil and #recipe.products > 0 then
               local product_name = recipe.products[1].name
               local product = game.item_prototypes[product_name] or game.fluid_prototypes[product_name] 
               local str = ""
               str = product.localised_description
               if str == nil or str == "" then
                  str = "No description found for this item"
               end
               printout(str, pindex)
            else
               printout("No description found, menu error", pindex)
            end
         elseif players[pindex].building.sector <= #players[pindex].building.sectors then
            local inventory = players[pindex].building.sectors[players[pindex].building.sector].inventory
            if inventory == nil or not inventory.valid then
               printout("No description found, menu error", pindex)
            end
            if players[pindex].building.sectors[players[pindex].building.sector].name ~= "Fluid" and players[pindex].building.sectors[players[pindex].building.sector].name ~= "Filters" and inventory.is_empty() then 
               printout("No description found, menu error", pindex)
               return
            end
            local stack = inventory[players[pindex].building.index]
            if stack and stack.valid_for_read and stack.valid == true then
               local str = ""
               if stack.prototype.place_result ~= nil then
                  str = stack.prototype.place_result.localised_description
               else
                  str = stack.prototype.localised_description
               end
               if str == nil or str == "" then
                  str = "No description found for this item"
               end
               printout(str, pindex)
            else
               printout("No description found, menu error", pindex)
            end
         end
      else --Another menu
         printout("Descriptions are not supported for this menu.", pindex)
      end

   end
end)

--Reads the custom info for the last indexed scanner item
script.on_event("item-info-last-indexed", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu then
      printout("Error: Cannot check scanned item descriptions while in a menu",pindex)
      return
   end
   local ent = players[pindex].last_indexed_ent
   if ent == nil or not ent.valid then
      printout("Cannot find the scanned item, note that most resources need to be examined from up close",pindex)--laterdo find a workaround for aggregate ents 
      return
   end
   local str = ent.localised_description
   if str == nil or str == "" then
      str = "No description found for this entity"
   end
   printout(str, pindex)
end)

--Gives in-game time. The night darkness is from 11 to 13, and peak daylight hours are 18 to 6.
--For realism, if we adjust by 12 hours, we get 23 to 1 as midnight and 6 to 18 as peak solar.
script.on_event("read-time-and-research-progress", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local surf = game.get_player(pindex).surface
   local hour = math.floor((24*surf.daytime + 12) % 24)
   local minute = math.floor((24* surf.daytime - math.floor(24*surf.daytime)) * 60)
   local progress = math.floor(game.get_player(pindex).force.research_progress* 100)
   local tech = game.get_player(pindex).force.current_research
   if tech ~= nil then
      printout("The local time is " .. hour .. ":" .. string.format("%02d", minute) .. ", Researching " .. game.get_player(pindex).force.current_research.name .. ", " .. progress .. "%", pindex)
   else
      printout("The local time is " .. hour .. ":" .. string.format("%02d", minute), pindex)
   end
   if players[pindex].vanilla_mode then
      game.get_player(pindex).open_technology_gui()
   end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local stack = game.get_player(pindex).cursor_stack
   local new_item_name = ""
   if stack and stack.valid_for_read then 
      new_item_name = stack.name
   end
   if players[pindex].previous_hand_item_name ~= new_item_name then
      players[pindex].previous_hand_item_name = new_item_name
      players[pindex].building_direction_lag = true
      read_hand(pindex)
   end
   sync_build_arrow(pindex)
end)


function ensure_global_structures_are_up_to_date()
   global.forces = global.forces or {}
   global.players = global.players or {}
   players = global.players
   for pindex, player in pairs(game.players) do
      initialize(player)
   end
   
   global.entity_types = {}
   entity_types = global.entity_types
   
   local types = {}
   for _, ent in pairs(game.entity_prototypes) do
      if types[ent.type] == nil and ent.weight == nil and (ent.burner_prototype ~= nil or ent.electric_energy_source_prototype~= nil or ent.automated_ammo_count ~= nil)then
         types[ent.type] = true
      end
   end
   
   for i, type in pairs(types) do
      table.insert(entity_types, i)
   end
   table.insert(entity_types, "container")
   
   global.production_types = {}
   production_types = global.production_types
   
   local ents = game.entity_prototypes
   local types = {}
   for i, ent in pairs(ents) do
--      if (ent.get_inventory_size(defines.inventory.fuel) ~= nil or ent.get_inventory_size(defines.inventory.chest) ~= nil or ent.get_inventory_size(defines.inventory.assembling_machine_input) ~= nil) and ent.weight == nil then
      if ent.speed == nil and ent.consumption == nil and (ent.burner_prototype ~= nil or ent.mining_speed ~= nil or ent.crafting_speed ~= nil or ent.automated_ammo_count ~= nil or ent.construction_radius ~= nil) then
         types[ent.type] = true
            end
   end
   for i, type in pairs(types) do
      table.insert(production_types, i)
   end
   table.insert(production_types, "transport-belt")   
   table.insert(production_types, "container")

   global.building_types = {}
   building_types = global.building_types

   local ents = game.entity_prototypes
   local types = {}
   for i, ent in pairs(ents) do
         if ent.is_building then
         types[ent.type] = true
            end
   end
   types["transport-belt"] = nil
   for i, type in pairs(types) do
      table.insert(building_types, i)
   end
   table.insert(building_types, "character")
   
   global.scheduled_events = global.scheduled_events or {}
   
end

script.on_load(function()
   players = global.players
   entity_types = global.entity_types
   production_types = global.production_types
   building_types = global.building_types
end)

script.on_configuration_changed(ensure_global_structures_are_up_to_date)
script.on_init(ensure_global_structures_are_up_to_date)


script.on_event(defines.events.on_cutscene_cancelled, function(event)
   pindex = event.player_index
   check_for_player(pindex)
   rescan(pindex)
end)

script.on_event(defines.events.on_player_created, function(event)
   initialize(game.players[event.player_index])
   if not game.is_multiplayer() then
      printout("Press tab to continue.", 0)
   end
end)

script.on_event(defines.events.on_gui_closed, function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   players[pindex].move_queue = {}
--   rescan(pindex)
   if players[pindex].in_menu == true and players[pindex].menu ~= "prompt"then
      if players[pindex].menu == "inventory" then
         game.get_player(pindex).play_sound{path="Close-Inventory-Sound"}
      elseif players[pindex].menu == "travel" or players[pindex].menu == "structure-travel" and event.element ~= nil then
         game.get_player(pindex).game_view_settings.update_entity_selection = true
         event.element.destroy()
      end
      players[pindex].in_menu = false
      players[pindex].menu = "none"
      players[pindex].item_selection = false
      players[pindex].item_cache = {}
      players[pindex].item_selector = {
         index = 0,
         group = 0,
         subgroup = 0
      }
      players[pindex].building.item_selection = false
   end
end)

script.on_event("save-game-manually", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   game.auto_save("manual")
   printout("Saving Game, please do not quit yet.", pindex)

end)

--Reads flying text
script.on_nth_tick(10, function(event)
   for pindex, player in pairs(players) do
      if player.allow_reading_flying_text == nil or player.allow_reading_flying_text == true then
         if player.past_flying_texts == nil then
            player.past_flying_texts = {}
         end
         local flying_texts = {}
         local search = {
            type = "flying-text",
            position = player.cursor_pos,
            radius = 80,
         }
         
         for _, ftext in pairs(game.get_player(pindex).surface.find_entities_filtered(search)) do
            local id = ftext.text
            if type(id) == 'table' then 
               id = serpent.line(id)
            end
            flying_texts[id] = (flying_texts[id] or 0) + 1
         end
         for id, count in pairs(flying_texts) do
            if count > (player.past_flying_texts[id] or 0) then
               local ok, local_text = serpent.load(id)
               if ok then 
                  printout(local_text,pindex)
               end
            end
         end
         player.past_flying_texts = flying_texts
      end
   end
end)

walk_type_speech={
   "Telestep enabled",
   "Step by walk enabled",
   "Walking smoothly enabled"
}

script.on_event("toggle-walk",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   reset_bump_stats(pindex)
   players[pindex].move_queue = {}
   if players[pindex].walk == 0 then --Mode 1 (walk-by-step) is temporarily disabled until it comes back as an in game setting.
      players[pindex].walk = 2
      game.get_player(pindex).character_running_speed_modifier = 0  -- 100% + 0 = 100%
   else--walk == 1 or walk == 2
      players[pindex].walk = 0
      game.get_player(pindex).character_running_speed_modifier = -1 -- 100% - 100% = 0%
   end
   --players[pindex].walk = (players[pindex].walk + 1) % 3
   printout(walk_type_speech[players[pindex].walk +1], pindex)
end)

function fix_walk(pindex)
   if not check_for_player(pindex) then
      return
   end
   if game.get_player(pindex).character == nil or game.get_player(pindex).character.valid == false then
      return
   end
   if players[pindex].walk == 0 then
      game.get_player(pindex).character_running_speed_modifier = -1 -- 100% - 100% = 0%
   else--walk > 0
      game.get_player(pindex).character_running_speed_modifier =  0 -- 100% + 0 = 100%
   end
end

--Toggle building while walking
script.on_event("toggle-build-lock", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if not (players[pindex].in_menu == true) then
      if players[pindex].build_lock == true then
         players[pindex].build_lock = false
         printout("Build lock disabled.", pindex)
      else
         players[pindex].build_lock = true
         printout("Build lock enabled", pindex)
      end
   end
end)

script.on_event("toggle-vanilla-mode",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   players[pindex].vanilla_mode = not players[pindex].vanilla_mode
   game.get_player(pindex).play_sound{path = "utility/confirm"}
   if players[pindex].vanilla_mode then
      game.get_player(pindex).print("Vanilla mode : ON")
      players[pindex].walk = 2
      game.get_player(pindex).character_running_speed_modifier = 0
      players[pindex].hide_cursor = true
   else
      game.get_player(pindex).print("Vanilla mode : OFF")
      players[pindex].hide_cursor = false
   end
end)

script.on_event("toggle-cursor-hiding",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].hide_cursor == nil or players[pindex].hide_cursor == false then
      players[pindex].hide_cursor = true
   else
      players[pindex].hide_cursor = false
   end
   game.get_player(pindex).play_sound{path = "utility/confirm"}
   if players[pindex].hide_cursor then
      game.get_player(pindex).print("Cursor hiding : ON")
   else
      game.get_player(pindex).print("Cursor hiding : OFF")
   end
end)

script.on_event("clear-renders",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   game.get_player(pindex).gui.screen.clear()
   
   rendering.clear()
   for pindex, player in pairs(players) do
      player.cursor_ent_highlight_box = nil
      player.cursor_tile_highlight_box = nil
      player.building_footprint = nil
      player.building_direction_arrow = nil
      player.overhead_sprite = nil
      player.overhead_circle = nil
      player.custom_GUI_frame = nil
      player.custom_GUI_sprite = nil
   end
   printout("Cleared renders",pindex)
end)

script.on_event("recalibrate-zoom",function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   fix_zoom(pindex)
end)

script.on_event("read-hand",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   read_hand(pindex)
end)

--Empties hand and opens the item from the player/building inventory
script.on_event("locate-hand-in-inventory",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu == false then
      locate_hand_in_player_inventory(pindex)
   elseif players[pindex].menu == "inventory" then
      locate_hand_in_player_inventory(pindex)
   elseif players[pindex].menu == "building" then
      locate_hand_in_building_output_inventory(pindex)
   else
      printout("Cannot locate items in this menu", pindex)
   end
end)

--Empties hand and opens the item from the crafting menu
script.on_event("locate-hand-in-crafting-menu",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   locate_hand_in_crafting_menu(pindex)
end)

--ENTER KEY by default
script.on_event("menu-search-open",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu == false then
      return
   end
   if players[pindex].menu == "train_menu" then
      return
   end
   if game.get_player(pindex).vehicle ~= nil then
      return
   end
   if event.tick - players[pindex].last_menu_search_tick < 5 then
      return
   end
   menu_search_open(pindex)
end)

script.on_event("menu-search-get-next",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu == false then
      return
   end
   local str = players[pindex].menu_search_term
   if str == nil or str == "" then
      printout("Press ENTER to start typing in a search term",pindex)
      return
   end
   menu_search_get_next(pindex,str)
end)

script.on_event("menu-search-get-last",function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu == false then
      return
   end
   local str = players[pindex].menu_search_term
   if str == nil or str == "" then
      printout("Press ENTER to start typing in a search term",pindex)
      return
   end
   menu_search_get_last(pindex,str)
end)

script.on_event("open-warnings-menu", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) or players[pindex].vanilla_mode then
      return
   end
   if players[pindex].in_menu == false or game.get_player(pindex).opened_gui_type == defines.gui_type.production then
      players[pindex].warnings.short = scan_for_warnings(30, 30, pindex)
      players[pindex].warnings.medium = scan_for_warnings(100, 100, pindex)
      players[pindex].warnings.long = scan_for_warnings(500, 500, pindex)
      players[pindex].warnings.index = 1
      players[pindex].warnings.sector = 1
      players[pindex].category = 1
      players[pindex].menu = "warnings"
      players[pindex].in_menu = true
      players[pindex].move_queue = {}
      game.get_player(pindex).play_sound{path = "Open-Inventory-Sound"}
      printout("Short Range: " .. players[pindex].warnings.short.summary, pindex)
   else
      printout("Another menu is open. ",pindex)
   end
end)

script.on_event("open-fast-travel-menu", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) or players[pindex].vanilla_mode then
      return
   end
   if players[pindex].in_menu == false and game.get_player(pindex).driving == false and game.get_player(pindex).opened == nil then
      game.get_player(pindex).game_view_settings.update_entity_selection = false
      game.get_player(pindex).selected = nil

      players[pindex].menu = "travel"
      players[pindex].in_menu = true
      players[pindex].move_queue = {}
      players[pindex].travel.index = {x = 1, y = 0}
      players[pindex].travel.creating = false
      printout("Navigate up and down to select a fast travel location, and jump to it with LEFT BRACKET.  Alternatively, select an option by navigating left and right.", pindex)
      local screen = game.get_player(pindex).gui.screen
      local frame = screen.add{type = "frame", name = "travel"}
      frame.bring_to_front()
      frame.force_auto_center()
      frame.focus()
      game.get_player(pindex).opened = frame      
   elseif players[pindex].in_menu or game.get_player(pindex).opened ~= nil then
      printout("Another menu is open.", pindex)
   elseif game.get_player(pindex).driving then
      printout("Cannot fast travel from inside a vehicle", pindex)
   end
   
   --Report disconnect error because the V key normally disconnects rolling stock if driving.
   local vehicle = nil
   if game.get_player(pindex).vehicle ~= nil and game.get_player(pindex).vehicle.train ~= nil then
      vehicle = game.get_player(pindex).vehicle
      local connected = 0
      if vehicle.get_connected_rolling_stock(defines.rail_direction.front) ~= nil then
         connected = connected + 1
      end
      if vehicle.get_connected_rolling_stock(defines.rail_direction.back) ~= nil then
         connected = connected + 1
      end
      if connected == 0 then
         printout("Warning, this vehicle was disconnected. Please review mod settings.", pindex)
         --Attempt to reconnect (does not work)
         --vehicle.connect_rolling_stock(defines.rail_direction.front)
         --vehicle.connect_rolling_stock(defines.rail_direction.back)
      end
   end

end)

--GUI action confirmed, such as by pressing ENTER
script.on_event(defines.events.on_gui_confirmed,function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].menu == "travel" then
      if players[pindex].travel.creating then
         players[pindex].travel.creating = false
         table.insert(global.players[pindex].travel, {name = event.element.text, position = players[pindex].cursor_pos})
         table.sort(global.players[pindex].travel, function(k1, k2)
            return k1.name < k2.name
         end)
         printout("Fast travel point created at " .. math.floor(players[pindex].cursor_pos.x) .. ", " .. math.floor(players[pindex].cursor_pos.y), pindex)
      elseif players[pindex].travel.renaming then
         players[pindex].travel.renaming = false
         global.players[pindex].travel[players[pindex].travel.index.y].name = event.element.text
         read_travel_slot(pindex)
      end
      players[pindex].travel.index.x = 1
      event.element.destroy()
   elseif players[pindex].train_menu.renaming == true then
      players[pindex].train_menu.renaming = false
      local result = event.element.text
      if result == nil or result == "" then 
         result = "unknown"
      end
      set_train_name(players[pindex].train_menu.locomotive.train, result)
      printout("Train renamed to " .. result .. ", menu closed.", pindex)
      event.element.destroy()
      train_menu_close(pindex, false)
   elseif players[pindex].train_stop_menu.renaming == true then
      players[pindex].train_stop_menu.renaming = false
      local result = event.element.text
      if result == nil or result == "" then 
         result = "unknown"
      end
      players[pindex].train_stop_menu.stop.backer_name = result
      printout("Train stop renamed to " .. result .. ", menu closed.", pindex)
      event.element.destroy()
      train_stop_menu_close(pindex, false)
   elseif players[pindex].roboport_menu.renaming == true then
      players[pindex].roboport_menu.renaming = false
      local result = event.element.text
      if result == nil or result == "" then 
         result = "unknown"
      end
      set_network_name(players[pindex].roboport_menu.port, result)
      printout("Network renamed to " .. result .. ", menu closed.", pindex)
      event.element.destroy()
      roboport_menu_close(pindex)
   elseif players[pindex].entering_search_term == true then
      local term = string.lower(event.element.text)
      event.element.focus()
      players[pindex].menu_search_term = term
      if term ~= "" then 
         printout("Searching for " .. term .. ", go through results with 'SHIFT + ENTER' or 'CONTROL + ENTER' ",pindex)
      end
      event.element.destroy()
      players[pindex].menu_search_frame.destroy()
   end
   players[pindex].last_menu_search_tick = event.tick
end)   

script.on_event("open-structure-travel-menu", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) or players[pindex].vanilla_mode then
      return
   end
   if players[pindex].in_menu == false then
      game.get_player(pindex).game_view_settings.update_entity_selection = false
      game.get_player(pindex).selected = nil
      players[pindex].menu = "structure-travel"
      players[pindex].in_menu = true
      players[pindex].move_queue = {}
      players[pindex].structure_travel.direction = "none"
      local ent = get_selected_ent(pindex)
      local initial_scan_radius = 50
      if ent ~= nil and ent.valid and ent.unit_number ~= nil and building_types[ent.type] then
         players[pindex].structure_travel.current = ent.unit_number
         players[pindex].structure_travel.network = compile_building_network(ent, initial_scan_radius,pindex)
      else
         ent = game.get_player(pindex).character
         players[pindex].structure_travel.current = ent.unit_number
         players[pindex].structure_travel.network = compile_building_network(ent, initial_scan_radius,pindex)      
      end
      local description = ""
      local network = players[pindex].structure_travel.network
      local current = players[pindex].structure_travel.current
      game.get_player(pindex).print("current id = " .. current)
      if network[current].north and #network[current].north > 0 then
         description = description .. ", " .. #network[current].north .. " connections north,"
      end
      if network[current].east  and #network[current].east > 0 then
         description = description .. ", " .. #network[current].east .. " connections east,"
      end
      if network[current].south and #network[current].south > 0 then
         description = description .. ", " .. #network[current].south .. " connections south,"
      end
      if network[current].west  and #network[current].west > 0 then
         description = description .. ", " .. #network[current].west .. " connections west,"
      end
      if description == "" then
         description = "No nearby buildings."
      end
      printout("Now at " .. ent.name .. " " .. extra_info_for_scan_list(ent,pindex,true) .. " " .. description .. ", Select a direction, confirm with same direction, and use perpendicular directions to select a target,  press left bracket to teleport to selection", pindex)
      local screen = game.get_player(pindex).gui.screen
      local frame = screen.add{type = "frame", name = "structure-travel"}
      frame.bring_to_front()
      frame.force_auto_center()
      frame.focus()
      game.get_player(pindex).opened = frame      
   else
      printout("Another menu is open. ",pindex)
   end

end)

script.on_event("nudge-up", function(event)
   nudge_key(defines.direction.north,event)
end)

script.on_event("nudge-down", function(event)
   nudge_key(defines.direction.south,event)
end)

script.on_event("nudge-left", function(event)
   nudge_key(defines.direction.west,event)
end)
script.on_event("nudge-right", function(event)
   nudge_key(defines.direction.east,event)
end)


script.on_event("train-menu-up", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then
      train_menu_up(pindex)
   end
end)

script.on_event("train-menu-down", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then
      train_menu_down(pindex)
   end
end)

script.on_event("train-menu-left", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then
      train_menu_left(pindex)
   end
end)

script.on_event("train-menu-right", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "train_menu" then
      train_menu_right(pindex)
   end
end)

script.on_event("cursor-one-tile-north", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].cursor then
      move_key(dirs.north,event, true)
   end
end)

script.on_event("cursor-one-tile-south", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].cursor then
      move_key(dirs.south,event, true)
   end
end)

script.on_event("cursor-one-tile-east", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].cursor then
      move_key(dirs.east,event, true)
   end
end)

script.on_event("cursor-one-tile-west", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   if players[pindex].cursor then
      move_key(dirs.west,event, true)
   end
end)

script.on_event("set-splitter-input-priority-left", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   if not ent then
      return
   elseif ent.name == "splitter" then
      local result = set_splitter_priority(ent, true, true, nil)
      printout(result,pindex)
   end
end)

script.on_event("set-splitter-input-priority-right", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent =  get_selected_ent(pindex)
   if not ent then
      return
   elseif ent.name == "splitter" then
      local result = set_splitter_priority(ent, true, false, nil)
      printout(result,pindex)
   end
end)

script.on_event("set-splitter-output-priority-left", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   if not ent then
      return
   end
   if ent.name == "splitter" then
      local result = set_splitter_priority(ent, false, true, nil)
      printout(result,pindex)
   end
end)

script.on_event("set-splitter-output-priority-right", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local ent = get_selected_ent(pindex)
   if not ent then
      return
   end
   --Build left turns on end rails
   if ent.name == "splitter" then
      local result = set_splitter_priority(ent, false, false, nil)
      printout(result,pindex)
   end
end)

script.on_event("set-splitter-filter", function(event)
   pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end

   if players[pindex].in_menu then
      if players[pindex].menu == "building" then
         return
      end
   else
      --Not in a menu
      local stack = game.get_player(pindex).cursor_stack
      local ent =  get_selected_ent(pindex)
      if stack == nil or not stack.valid_for_read or not stack.valid then
         if ent and ent.name == "splitter" then
            --Clear the filter
            local result = set_splitter_priority(ent, nil, nil, nil, true)
            printout(result,pindex)
         end
         return
      elseif ent and ent.name == "splitter" then
         --Set the filter
         local result = set_splitter_priority(ent, nil, nil, stack)
         printout(result,pindex)
      end
   end
end)

-- G is used to connect rolling stock
script.on_event("connect-rail-vehicles", function(event)
   local pindex = event.player_index
   local vehicle = nil
   if not check_for_player(pindex) or players[pindex].in_menu then
      return
   end
   local ent = get_selected_ent(pindex)
   if game.get_player(pindex).vehicle ~= nil and game.get_player(pindex).vehicle.train ~= nil then
      vehicle = game.get_player(pindex).vehicle
   elseif ent ~= nil and ent.valid and ent.train ~= nil then
      vehicle = ent
   end
   
   if vehicle ~= nil then
      --Connect rolling stock (or check if the default key bindings make the connection)
      local connected = 0
      if vehicle.connect_rolling_stock(defines.rail_direction.front) then
         connected = connected + 1
      end
      if  vehicle.connect_rolling_stock(defines.rail_direction.back) then
         connected = connected + 1
      end
      if connected > 0 then
         printout("Connected this vehicle.", pindex)
      else
         connected = 0
         if vehicle.get_connected_rolling_stock(defines.rail_direction.front) ~= nil then
            connected = connected + 1
         end
         if vehicle.get_connected_rolling_stock(defines.rail_direction.back) ~= nil then
            connected = connected + 1
         end
         if connected > 0 then
            printout("Connected this vehicle.", pindex)
         else
            printout("Nothing was connected.", pindex)
         end
      end
   end 
end)

--SHIFT + G is used to disconnect rolling stock
script.on_event("disconnect-rail-vehicles", function(event)
   local pindex = event.player_index
   local vehicle = nil
   if not check_for_player(pindex) or players[pindex].in_menu then
      return
   end
   local ent = get_selected_ent(pindex)
   if game.get_player(pindex).vehicle ~= nil and game.get_player(pindex).vehicle.train ~= nil then
      vehicle = game.get_player(pindex).vehicle
   elseif ent ~= nil and ent.train ~= nil then
      vehicle = ent
   end
   
   if vehicle ~= nil then
      --Disconnect rolling stock
      local disconnected = 0
      if vehicle.disconnect_rolling_stock(defines.rail_direction.front) then
         disconnected = disconnected + 1
      end
      if vehicle.disconnect_rolling_stock(defines.rail_direction.back) then
         disconnected = disconnected + 1
      end
      if disconnected > 0 then
         printout("Disconnected this vehicle.", pindex)
      else
         local connected = 0
         if vehicle.get_connected_rolling_stock(defines.rail_direction.front) ~= nil then
            connected = connected + 1
         end
         if vehicle.get_connected_rolling_stock(defines.rail_direction.back) ~= nil then
            connected = connected + 1
         end
         if connected > 0 then
            printout("Disconnection error.", pindex)
         else
            printout("Disconnected this vehicle.", pindex)
         end
      end
   end
end)

script.on_event("inventory-read-armor-stats", function(event)
   local pindex = event.player_index
   local vehicle = nil
   if not check_for_player(pindex) or not players[pindex].in_menu then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "inventory" then
	  local result = read_armor_stats(pindex)
	  --game.get_player(pindex).print(result)--
	  printout(result,pindex)
   end   
end)

script.on_event("inventory-read-equipment-list", function(event)
   local pindex = event.player_index
   local vehicle = nil
   if not check_for_player(pindex) or not players[pindex].in_menu then
      return
   end
   if players[pindex].in_menu and players[pindex].menu == "inventory" then
	  local result = read_equipment_list(pindex)
	  --game.get_player(pindex).print(result)--
	  printout(result,pindex)
   end   
end)

script.on_event("inventory-remove-all-equipment-and-armor", function(event)
   local pindex = event.player_index
   local vehicle = nil
   if not check_for_player(pindex) then
      return
   end
   
   if players[pindex].in_menu and players[pindex].menu == "inventory" then
	  local result = remove_equipment_and_armor(pindex)
	  --game.get_player(pindex).print(result)--
	  printout(result,pindex)
   end 
   
end)

--**Use this key to test stuff (ALT-G)
script.on_event("debug-test-key", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   local p = game.get_player(pindex)
   local ent =  get_selected_ent(pindex)
   local stack = game.get_player(pindex).cursor_stack
   
   game.print(direction_lookup(p.walking_state.direction))
   
   --Recolor cursor boxes if multiplayer
   if true then
      set_cursor_colors_to_player_colors(pindex)
   end

end)

--Attempt to launch a rocket
script.on_event("launch-rocket", function(event)
   local pindex = event.player_index
   local ent = get_selected_ent(pindex)
   if not check_for_player(pindex) then
      return
   end
   --For rocket entities, return the silo instead
   if ent and (ent.name == "rocket-silo-rocket-shadow" or ent.name == "rocket-silo-rocket") then
      local ents = ent.surface.find_entities_filtered{position = ent.position, radius = 20, name = "rocket-silo"}
      for i,silo in ipairs(ents) do
	     ent = silo
      end
   end
   --Try to launch from the silo
   if ent ~= nil and ent.valid and ent.name == "rocket-silo" then
      local try_launch = ent.launch_rocket()
      if try_launch then
	     printout("Launch successful!",pindex)
      else
	     printout("Not ready to launch!",pindex)
      end
   end
end)


script.on_event("logistic-request-read", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   logistics_info_key_handler(pindex)
end)

script.on_event("logistic-request-increment-min", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   logistics_request_increment_min_handler(pindex)
end)

script.on_event("logistic-request-decrement-min", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   logistics_request_decrement_min_handler(pindex)
end)

script.on_event("logistic-request-increment-max", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   logistics_request_increment_max_handler(pindex)
end)

script.on_event("logistic-request-decrement-max", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   logistics_request_decrement_max_handler(pindex)
end)

script.on_event("logistic-request-toggle-personal-logistics", function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   logistics_request_toggle_handler(pindex)
end)

script.on_event(defines.events.on_gui_opened, function(event)
   local pindex = event.player_index
   if not check_for_player(pindex) then
      return
   end
   players[pindex].move_queue = {}
   if event.gui_type == defines.gui_type.controller and players[pindex].menu == "none" and event.tick - players[pindex].last_menu_toggle_tick < 5 then
      --We close the player GUI if closing/opening another menu toggles the player GUI screen
      game.get_player(pindex).opened = nil
      --game.print("Closed an extra GUI",{volume_modifier = 0})--**laterdo enable these and review what doess what
   elseif game.get_player(event.player_index).opened ~= nil then
      players[pindex].in_menu = true
      --game.print("Opened an extra GUI",{volume_modifier = 0})--**laterdo enable these and review what doess what
   end
end)

script.on_event(defines.events.on_chunk_charted,function(event)
   pindex = event.force.players[1].index
   if not check_for_player(pindex) then
   end
   if players[pindex].mapped[pos2str(event.position)] ~= nil then
      return
   end
   players[pindex].mapped[pos2str(event.position)] = true
   local islands = find_islands(game.surfaces[event.surface_index], event.area, pindex)

   if table_size(islands) > 0 then
      for i, v in pairs(islands) do
         if players[pindex].resources[i] == nil then
            players[pindex].resources[i] = {
               patches = {},
               queue = {},
               index = 1,
               positions = {}
            }
         end
         local merged_groups = {}
         local many2many = {}
         if players[pindex].resources[i].queue[pos2str(event.position)] ~= nil then
            for dir, positions in pairs(players[pindex].resources[i].queue[pos2str(event.position)]) do
--               islands[i].neighbors[dir] = nil
               for i3, pos in pairs(positions) do
                  local dirs = {dir - 1, dir, dir + 1}
                  if dir == 0 then dirs[1] = 7 end
                  local new_edges = {}
                  for i1, d in ipairs(dirs) do
                     new_edges[pos2str(offset_position(str2pos(pos), d, -1))] = true
                  end
                  local adj = {}
                  for d = 0, 7 do
                     adj[d] = pos2str(offset_position(str2pos(pos), d, 1))         
                  end
                  local edge = false
                  for d, p in ipairs(adj) do
                     if new_edges[p] then
                        if islands[i].resources[p] ~= nil then
                           local island_group = islands[i].resources[p].group
                           if merged_groups[island_group] == nil then
                              merged_groups[island_group] = {}
                           end
                           merged_groups[island_group][players[pindex].resources[i].positions[pos]] = true
                        else
                           edge = true
                        end
                     else
                        if players[pindex].resources[i].positions[p] == nil then
                           edge = true
                        end
                     end
                  
                  end
                  if edge == false then
                     local group = players[pindex].resources[i].positions[pos]
                     players[pindex].resources[i].patches[group].edges[pos] = nil
                  end
                  for p, b in pairs(new_edges) do
                     if islands[i].resources[p] ~= nil then
                        local adj = {}
                        for d = 0, 7 do
                           adj[d] = pos2str(offset_position(str2pos(pos), d, 1))         
                        end
                        local edge = false
                        for d, p1 in ipairs(adj) do
                           if islands[i].resources[p1] == nil and players[pindex].resources[i].positions[p1] == nil then
                              edge = true
                           end
                        end
                        if edge == false then
                           islands[i].resources[p].edge = false
                           islands[i].edges[p]= nil
                        else
                           islands[i].edges[p]= false
                        end
                     end
   
                  end
               
               end
            end
         end
         for island_group, resource_groups in pairs(merged_groups) do
            local matches = {}
            for i1, ref in ipairs(many2many) do
               local match = false
               for i2, v2 in pairs(resource_groups) do
                  if match then
                     break
                  end
                  for i3, v3 in pairs(ref["old"]) do
                     if i2 == i3 then
                        table.insert(matches, i1)
                        match = true
                        break
                     end
                  end
               end
            end
            local old = table.deepcopy(resource_group)
            if old ~= nil then
               local new = {}
               new[island_group] = true
               if table_size(matches) == 0 then
                  local entry = {}
                  entry["old"] = old
                  entry["new"] = new
                  table.insert(many2many, table.deepcopy(entry))
               else
                  table.sort(matches, function(k1, k2)
                     return k1 > k2
                 end)

                  for i1, merge_index in ipairs(matches) do
                     for i2, v2 in pairs(many2many[merge_index]["old"]) do
                        old[i2] = true
                     end
                     for i2, v2 in pairs(many2many[merge_index]["new"]) do
                        new[i2] = true
                     end
                     table.remove(many2many, merge_index)
                  end
                  local entry = {}
                  entry["old"] = old
                  entry["new"] = new

                  table.insert(many2many, table.deepcopy(entry)) 
               end
            end
         end
         for i1, entry in pairs(many2many) do
            for island_group, v2 in pairs(entry["new"]) do
               for resource_group, v3 in pairs(entry["old"]) do
                  merged_groups[island_group][resource_group] = true
               end
            end
         end

         for island_group, resource_groups in pairs(merged_groups) do
            local new_group = math.huge
            for resource_group, b in pairs(resource_groups) do
               new_group = math.min(new_group, resource_group)
            end
            for resource_group, b in pairs(resource_groups) do
               if new_group < resource_group and players[pindex].resources[i].patches ~= nil and players[pindex].resources[i].patches[resource_group] ~= nil and islands[i] ~= nil and islands[i].resources ~= nil and islands[i].resources[b] ~= nil then--**beta changed "p" to "b"
                  for i1, pos in pairs(players[pindex].resources[i].patches[resource_group].positions) do
                     players[pindex].resources[i].positions[pos] = new_group
                     players[pindex].resources[i].count = islands[i].resources[b].count--**beta "p" to "b"
                  end
                  table_concat(players[pindex].resources[i].patches[new_group].positions, players[pindex].resources[i].patches[resource_group].positions)
                  for pos, val in pairs(players[pindex].resources[i].patches[resource_group].edges) do
                     players[pindex].resources[i].patches[new_group].edges[pos] = val
                  end
                  players[pindex].resources[i].patches[resource_group] = nil
               end
            end
            for pos, val in pairs(islands[i].groups[island_group]) do
               players[pindex].resources[i].positions[pos] = new_group
if 'number' == type(players[pindex].resources[i].patches[new_group]) then new_group = players[pindex].resources[i].patches[new_group] end
               table.insert(players[pindex].resources[i].patches[new_group].positions, pos)
               if islands[i].edges[pos] ~= nil then
                  players[pindex].resources[i].patches[new_group].edges[pos] = islands[i].edges[pos]
               end
               islands[i].groups[island_group] = nil
            end
         end

         for dir, v1 in pairs(islands[i].neighbors) do
            local chunk_pos = pos2str(offset_position(event.position, dir, 1))
         if players[pindex].resources[i].queue[chunk_pos] == nil then
            players[pindex].resources[i].queue[chunk_pos] = {}
         end
            players[pindex].resources[i].queue[chunk_pos][dir] =  {}
         end
         for old_index , group in pairs(v.groups) do
            if true then
               local new_index = players[pindex].resources[i].index
               players[pindex].resources[i].patches[new_index] = {
                  positions = {},
                  edges = {}
               }
               players[pindex].resources[i].index = players[pindex].resources[i].index + 1
               for i2, pos in pairs(group) do
                  players[pindex].resources[i].positions[pos] = new_index
                  table.insert(players[pindex].resources[i].patches[new_index].positions, pos)
                  if islands[i].edges[pos] ~= nil then
                     players[pindex].resources[i].patches[new_index].edges[pos] = islands[i].edges[pos]
                     if islands[i].edges[pos] then
                        local position = str2pos(pos)
                        if area_edge(event.area, 0, position, i) then
   
                           local chunk_pos = pos2str(offset_position(event.position, 0, 1))
                           if players[pindex].resources[i].queue[chunk_pos][4] == nil then 
                              players[pindex].resources[i].queue[chunk_pos][4] = {}
                           end
                           table.insert(players[pindex].resources[i].queue[chunk_pos][4], pos)
                        end
                        if area_edge(event.area, 6, position, i) then
                           local chunk_pos = pos2str(offset_position(event.position, 6, 1))
                           if players[pindex].resources[i].queue[chunk_pos][2] == nil then 
                              players[pindex].resources[i].queue[chunk_pos][2] = {}
                           end
                           table.insert(players[pindex].resources[i].queue[chunk_pos][2], pos)
                        end
                        if area_edge(event.area, 4, position, i) then
                           local chunk_pos = pos2str(offset_position(event.position, 4, 1))
                           if players[pindex].resources[i].queue[chunk_pos][0] == nil then 
                              players[pindex].resources[i].queue[chunk_pos][0] = {}
                           end
                           table.insert(players[pindex].resources[i].queue[chunk_pos][0], pos)
                        end
                        if area_edge(event.area, 2, position, i) then
                           local chunk_pos = pos2str(offset_position(event.position, 2, 1))
                           if players[pindex].resources[i].queue[chunk_pos][6] == nil then 
                              players[pindex].resources[i].queue[chunk_pos][6] = {}
                           end
                           table.insert(players[pindex].resources[i].queue[chunk_pos][6], pos)
                        end
                        
                     end

                        
                  end
               end
            end
         end
      end
--      print(event.area.left_top.x .. " " .. event.area.left_top.y)
--      print(event.area.right_bottom.x .. " " .. event.area.right_bottom.y)
--      for name, obj in pairs(resources) do
--         print(name .. ": " .. table_size(obj.patches))
--      end
   end
end)


script.on_event(defines.events.on_entity_destroyed,function(event) --DOES NOT HAVE THE KEY PLAYER_INDEX
   local ent = nil  
   for pindex, player in pairs(players) do --If the destroyed entity is destroyed by any player, it will be detected. Laterdo consider logged out players etc?
      if players[pindex] ~= nil then 
         local try_ent = players[pindex].destroyed[event.registration_number]
         if try_ent ~= nil and try_ent.valid then
            ent = try_ent
         end
      end
   end
   if ent == nil then
      return
   end
   local str = pos2str(ent.position)
   if ent.type == "resource" then
      if ent.name ~= "crude-oil" and players[pindex].resources[ent.name].positions[str] ~= nil then--**beta added a check here to not run for nil "group"s...
         local group = players[pindex].resources[ent.name].positions[str]
         players[pindex].resources[ent.name].positions[str] = nil
         --game.get_player(pindex).print("Pos str: " .. str)
         --game.get_player(pindex).print("group: " .. group)
         players[pindex].resources[ent.name].patches[group].edges[str] = nil
         for i = 1, #players[pindex].resources[ent.name].patches[group].positions do
            if players[pindex].resources[ent.name].patches[group].positions[i] == str then
               table.remove(players[pindex].resources[ent.name].patches[group].positions, i)
               i = i - 1
            end
         end
         if #players[pindex].resources[ent.name].patches[group].positions == 0 then
            players[pindex].resources[ent.name].patches[group] = nil
            if table_size(players[pindex].resources[ent.name].patches) == 0 then
               players[pindex].resources[ent.name] = nil
            end
            return
         end
         for d = 0, 7 do
            local adj = pos2str(offset_position(ent.position, d, 1))         
            if players[pindex].resources[ent.name].positions[adj] == group then
               players[pindex].resources[ent.name].patches[group].edges[adj] = false
            end
         end
      end
   elseif ent.type == "tree" then
      local adj = {}
      adj[pos2str({x = math.floor(ent.area.left_top.x/32),y = math.floor(ent.area.left_top.y/32)})] = true
      adj[pos2str({x = math.floor(ent.area.right_bottom.x/32),y = math.floor(ent.area.left_top.y/32)})] = true
      adj[pos2str({x = math.floor(ent.area.left_top.x/32),y = math.floor(ent.area.right_bottom.y/32)})] = true
      adj[pos2str({x = math.floor(ent.area.right_bottom.x/32),y = math.floor(ent.area.right_bottom.y/32)})] = true
      for pos, val in pairs(adj) do
         --players[pindex].tree_chunks[pos].count = players[pindex].tree_chunks[pos].count - 1--**beta Forests need updating but these lines are incorrectly named
      end
   end
   players[pindex].destroyed[event.registration_number] = nil
end)

--Scripts regarding train state changes. NOTE: NO PINDEX
script.on_event(defines.events.on_train_changed_state,function(event)
   if event.train.state == defines.train_state.no_schedule then
      --Trains with no schedule are set back to manual mode
      event.train.manual_mode = true
   elseif event.train.state == defines.train_state.arrive_station then
      --Announce station to players on the train
	  for i,player in ipairs(event.train.passengers) do
         local stop = event.train.path_end_stop
		 if stop ~= nil then
         str = " Arriving at station " .. stop.backer_name .. " "
         players[player.index].last = str
         localised_print{"","out ",str}
		 end
      end
   elseif event.train.state == defines.train_state.on_the_path then --laterdo make this announce only when near another trainstop.
      --Announce station to players on the train
	  for i,player in ipairs(event.train.passengers) do
         local stop = event.train.path_end_stop
		 if stop ~= nil then
		    str = " Heading to station " .. stop.backer_name .. " "
			players[player.index].last = str
	        localised_print{"","out ",str}
		 end
      end
   elseif event.train.state == defines.train_state.wait_signal then
      --Announce the wait to players on the train
	  for i,player in ipairs(event.train.passengers) do
         local stop = event.train.path_end_stop
		 if stop ~= nil then
		    str = " Waiting at signal. "
			players[player.index].last = str
	        localised_print{"","out ",str}
		 end
      end
   end
end)

--[[
* Returns the direction of that entity from this entity based on the ratios of the x and y distances. 
* Returns 1 of 8 main directions, with a bias away from the 4 cardinal directions, to make it easier to align with them. 
* The deciding ratio is 1 to 4, meaning that for an object that is 100 tiles north, it can be offset by up to 25 tiles east or west before it stops being counted as "directly" in the north. 
* The arctangent of 1/4 is about 14 degrees, meaning that the field of view that directly counts as a cardinal direction is about 30 degrees, while for a diagonal direction it is about 60 degrees.]]
function get_direction_of_that_from_this(pos_that,pos_this)
   local diff_x = pos_that.x - pos_this.x
   local diff_y = pos_that.y - pos_this.y
   local dir = -1
   
   if math.abs(diff_x) > 4 * math.abs(diff_y) then --along east-west
      if diff_x > 0 then 
	     dir = defines.direction.east 
	  else 
	     dir = defines.direction.west 
	  end
   elseif math.abs(diff_y) > 4 * math.abs(diff_x) then --along north-south
      if diff_y > 0 then 
	     dir = defines.direction.south 
	  else 
	     dir = defines.direction.north 
	  end
   else --along diagonals
      if diff_x > 0 and diff_y > 0 then
	     dir = defines.direction.southeast
      elseif diff_x > 0 and diff_y < 0 then
	     dir = defines.direction.northeast
      elseif diff_x < 0 and diff_y > 0 then
	     dir = defines.direction.southwest
	  elseif diff_x < 0 and diff_y < 0 then
	     dir = defines.direction.northwest
	  elseif diff_x == 0 and diff_y == 0 then
        dir = 99--case for "it is right here"
     else
	     dir = -2
	  end
   end
   return dir
end

--[[
* Returns the direction of that entity from this entity based on the ratios of the x and y distances. 
* Returns 1 of 8 main directions, with each getting about equal representation (45 degrees). 
* The deciding ratio is 1 to 2.5, meaning that for an object that is 25 tiles north, it can be offset by up to 10 tiles east or west before it stops being counted as "directly" in the north. 
* The arctangent of 1/2.5 is about 22 degrees, meaning that the field of view that directly counts as a cardinal direction is about 44 degrees, while for a diagonal direction it is about 46 degrees.]]
function get_balanced_direction_of_that_from_this(pos_that,pos_this)
   local diff_x = pos_that.x - pos_this.x
   local diff_y = pos_that.y - pos_this.y
   local dir = -1
   
   if math.abs(diff_x) > 2.5 * math.abs(diff_y) then --along east-west
      if diff_x > 0 then 
	     dir = defines.direction.east 
	  else 
	     dir = defines.direction.west 
	  end
   elseif math.abs(diff_y) > 2.5 * math.abs(diff_x) then --along north-south
      if diff_y > 0 then 
	     dir = defines.direction.south 
	  else 
	     dir = defines.direction.north 
	  end
   else --along diagonals
      if diff_x > 0 and diff_y > 0 then
	     dir = defines.direction.southeast
      elseif diff_x > 0 and diff_y < 0 then
	     dir = defines.direction.northeast
      elseif diff_x < 0 and diff_y > 0 then
	     dir = defines.direction.southwest
	  elseif diff_x < 0 and diff_y < 0 then
	     dir = defines.direction.northwest
	  elseif diff_x == 0 and diff_y == 0 then
        dir = 99--case for "it is right here"
     else
	     dir = -2
	  end
   end
   return dir
end

--Directions lookup table, laterdo localise**
function direction_lookup(dir)
   local reading = "unknown"
   if dir < 0 then
      return "direction error 1"
   end
   
   if dir == dirs.north then
      reading = "North"
   elseif dir == dirs.northeast then
      reading = "Northeast"
   elseif dir == dirs.east then
      reading = "East"
   elseif dir == dirs.southeast then
      reading = "Southeast"
   elseif dir == dirs.south then
      reading = "South"
   elseif dir == dirs.southwest then
      reading = "Southwest"
   elseif dir == dirs.west then
      reading = "West"
   elseif dir == dirs.northwest then
      reading = "Northwest"
   elseif dir == 99 then --Internally defined
      reading = "Here"
   else
      reading = "unknown direction ID " .. dir
   end      
   return reading
end

--Spawns a lamp at the electric pole and uses its energy level to approximate the network satisfaction percentage with high accuracy
function get_electricity_satisfaction(electric_pole)
   local satisfaction = -1
   local test_lamp = electric_pole.surface.create_entity{name = "small-lamp", position = electric_pole.position, raise_built = false, force = electric_pole.force}
   satisfaction = math.ceil(test_lamp.energy * 9/8)--Experimentally found coefficient
   test_lamp.destroy{}
   return satisfaction
end

function get_electricity_flow_info(ent)
   local result = ""
   local power = 0
   local capacity = 0
   for i, v in pairs(ent.electric_network_statistics.output_counts) do
      power = power + (ent.electric_network_statistics.get_flow_count{name = i, input = false, precision_index = defines.flow_precision_index.five_seconds})
      local cap_add = 0
      for _, power_ent in pairs(ent.surface.find_entities_filtered{name=i,force = ent.force}) do
         if power_ent.electric_network_id == ent.electric_network_id then
            cap_add = cap_add + 1
         end
      end
      cap_add = cap_add * game.entity_prototypes[i].max_energy_production
      if game.entity_prototypes[i].type == "solar-panel" then
         cap_add = cap_add * ent.surface.solar_power_multiplier * (1-ent.surface.darkness)
      end
      capacity = capacity + cap_add   
   end
  power = power * 60
  capacity = capacity * 60
  result = result .. get_power_string(power) .. " being produced out of " .. get_power_string(capacity) .. " capacity, "
  return result
end

--Finds the neearest electric pole. Can be set to determine whether to check only for poles with electricity flow. Can call using only the first two parameters.
function find_nearest_electric_pole(ent, require_supplied, radius, alt_surface, alt_pos)
   local nearest = nil
   local retry = retry or 0
   local min_dist = 99999
   local poles = nil
   local require_supplied = require_supplied or false
   local radius = radius or 10
   local surface = nil
   local pos = nil
   if ent ~= nil and ent.valid then
      surface = ent.surface
	   pos = ent.position
   else
      surface = alt_surface
	  pos = alt_pos
   end
   
   --Scan nearby for electric poles, expand radius if not successful
   local poles = surface.find_entities_filtered{ type = "electric-pole" , position = pos , radius = radius}
   if poles == nil or #poles == 0 then
      if radius < 100 then
         radius = 100
         return find_nearest_electric_pole(ent, require_supplied, radius, alt_surface, alt_pos)
      elseif radius < 1000 then	 
         radius = 1000
         return find_nearest_electric_pole(ent, require_supplied, radius, alt_surface, alt_pos)
      elseif radius < 10000 then
         radius = 10000
         return find_nearest_electric_pole(ent, require_supplied, radius, alt_surface, alt_pos)
      else
         return nil, nil --Nothing within 10000 tiles!
      end
   end
   
   --Find the nearest among the poles with electric networks
   for i,pole in ipairs(poles) do
      --Check if the pole's network has power producers
	   local has_power = get_electricity_satisfaction(pole) > 0
      local dict = pole.electric_network_statistics.output_counts
      local network_producers = {}
      for name, count in pairs(dict) do
         table.insert(network_producers, {name = name, count = count})
      end
	   local network_producer_count = #network_producers --laterdo test again if this is working, it should pick up even 0.001% satisfaction...
      local dist = 0
	   if has_power or network_producer_count > 0 or (not require_supplied) then
	      dist = math.ceil(util.distance(pos, pole.position))
		   --Set as nearest if valid
		   if dist < min_dist then
		      min_dist = dist
			   nearest = pole
		   end
	   end
   end
   --Return the nearst found, possibly nil
   if nearest == nil then
      if radius < 100 then
	     radius = 100
		 return find_nearest_electric_pole(ent, require_supplied, radius, alt_surface, alt_pos)
	  elseif radius < 1000 then	 
	     radius = 1000
		 return find_nearest_electric_pole(ent, require_supplied, radius, alt_surface, alt_pos)
	  elseif radius < 10000 then
	     radius = 10000
		 return find_nearest_electric_pole(ent, require_supplied, radius, alt_surface, alt_pos)
	  else
	     return nil, nil --Nothing within 10000 tiles!
	  end
   end
   rendering.draw_circle{color = {1, 1, 0}, radius = 2, width = 2, target = nearest.position, surface = nearest.surface, time_to_live = 60}
   return nearest, min_dist
end


--Returns an info string on the nearest supplied electric pole for this entity.
function report_nearest_supplied_electric_pole(ent)
   local result = ""
   local pole, dist = find_nearest_electric_pole(ent, true)
   local dir = -1
   if pole ~= nil then
      dir = get_direction_of_that_from_this(pole.position,ent.position)
      result = "The nearest powered electric pole is " .. dist .. " tiles to the " .. direction_lookup(dir)
   else
      result = "And there are no powered electric poles within ten thousand tiles. Generators may be out of energy."
   end
   return result
end

--Reports which part of the selected entity has the cursor. E.g. southwest corner, center...
function get_entity_part_at_cursor(pindex)
	 --First check if there is an entity at the cursor
	 local p = game.get_player(pindex)
	 local x = players[pindex].cursor_pos.x
	 local y = players[pindex].cursor_pos.y
	 local ents = p.surface.find_entities_filtered{position = {x = x,y = y}}
	 local north_same = false
	 local south_same = false
	 local east_same = false
	 local west_same = false
	 local location = nil
	 if #ents > 0 then
		--Report which part of the entity the cursor covers.
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = x+0 ,y = y-1}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = x+0 ,y = y+1}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = x-1 ,y = y-0}, surface = p.surface, time_to_live = 30}
      rendering.draw_circle{color = {1, 0.0, 0.5},radius = 0.1,width = 2,target = {x = x+1 ,y = y-0}, surface = p.surface, time_to_live = 30}
      
		local ent_north = p.surface.find_entities_filtered{position = {x = x,y = y-1}}
		if #ent_north > 0 and ent_north[1].unit_number == ents[1].unit_number then north_same = true 
      elseif #ent_north > 1 and ent_north[2].unit_number == ents[1].unit_number then north_same = true end
		local ent_south = p.surface.find_entities_filtered{position = {x = x,y = y+1}}
		if #ent_south > 0 and ent_south[1].unit_number == ents[1].unit_number then south_same = true 
      elseif #ent_south > 1 and ent_south[2].unit_number == ents[1].unit_number then south_same = true end
		local ent_east = p.surface.find_entities_filtered{position = {x = x+1,y = y}}
		if #ent_east > 0 and ent_east[1].unit_number == ents[1].unit_number then east_same = true 
      elseif #ent_east > 1 and ent_east[2].unit_number == ents[1].unit_number then east_same = true end
		local ent_west = p.surface.find_entities_filtered{position = {x = x-1,y = y}}
		if #ent_west > 0 and ent_west[1].unit_number == ents[1].unit_number then west_same = true 
      elseif #ent_west > 1 and ent_west[2].unit_number == ents[1].unit_number then west_same = true end
		
		if north_same and south_same then
		   if east_same and west_same then
			  location = "center"
		   elseif east_same and not west_same then
			  location = "west edge"
		   elseif not east_same and west_same then
			  location = "east edge"
		   elseif not east_same and not west_same then
			  location = "middle"
		   end
		elseif north_same and not south_same then
		   if east_same and west_same then
			  location = "south edge"
		   elseif east_same and not west_same then
			  location = "southwest corner"
		   elseif not east_same and west_same then
			  location = "southeast corner"
		   elseif not east_same and not west_same then
			  location = "south tip"
		   end
		elseif not north_same and south_same then
		   if east_same and west_same then
			  location = "north edge"
		   elseif east_same and not west_same then
			  location = "northwest corner"
		   elseif not east_same and west_same then
			  location = "northeast corner"
		   elseif not east_same and not west_same then
			  location = "north tip"
		   end
		elseif not north_same and not south_same then
		   if east_same and west_same then
			  location = "middle"
		   elseif east_same and not west_same then
			  location = "west tip"
		   elseif not east_same and west_same then
			  location = "east tip"
		   elseif not east_same and not west_same then
			  location = " "
		   end
		end
	 end
	 return location
end

--Set the input priority or the output priority or filter for a splitter
function set_splitter_priority(splitter, is_input, is_left, filter_item_stack, clear)
   local clear = clear or false
   local result = "no message"
   local filter = splitter.splitter_filter
   
   if clear then
      splitter.splitter_filter = nil
      filter = splitter.splitter_filter
      result = "Cleared splitter filter"
      splitter.splitter_output_priority = "none"
   elseif filter_item_stack ~= nil and filter_item_stack.valid_for_read then
      splitter.splitter_filter = filter_item_stack.prototype
      filter = splitter.splitter_filter
      result = "filter set to " .. filter_item_stack.name
      if splitter.splitter_output_priority == "none" then
         splitter.splitter_output_priority = "left"
         result = result .. ", from the left"
      end
   elseif is_input and     is_left then
      if splitter.splitter_input_priority == "left" then
         splitter.splitter_input_priority = "none"
         result = "equal input priority"
      else
         splitter.splitter_input_priority = "left"
         result = "left input priority"
      end
   elseif is_input and not is_left then
      if splitter.splitter_input_priority == "right" then
         splitter.splitter_input_priority = "none"
         result = "equal input priority"
      else
         splitter.splitter_input_priority = "right"
         result = "right input priority"
      end
   elseif not is_input and is_left then
      if splitter.splitter_output_priority == "left" then
         if filter == nil then
            splitter.splitter_output_priority = "none"
            result = "equal output priority"
         else
            result = "left filter output"
         end
      else
         if filter == nil then
            splitter.splitter_output_priority = "left"
            result = "left output priority"
         else
            splitter.splitter_output_priority = "left"
            result = "left filter output"
         end
      end
   elseif not is_input and not is_left then
      if splitter.splitter_output_priority == "right" then
         if filter == nil then
            splitter.splitter_output_priority = "none"
            result = "equal output priority"
         else
            result = "right filter output"
         end
      else
         if filter == nil then
            splitter.splitter_output_priority = "right"
            result = "right output priority"
         else
            splitter.splitter_output_priority = "right"
            result = "right filter output"
         end
      end
   else
      result = "Splitter config error"
   end
   
   return result
end

function rotate_90(dir)
   return (dir + dirs.east) % (2 * dirs.south)
end

function rotate_180(dir)
   return (dir + dirs.south) % (2 * dirs.south)
end

function sync_build_arrow(pindex)
   local player = players[pindex]
   local stack = game.get_player(pindex).cursor_stack
   if player.building_direction == nil then
      player.building_direction = 0
   end
   local dir = player.building_direction * dirs.east
   local dir_indicator = player.building_direction_arrow
   local p_dir = player.player_direction
   if stack and stack.valid_for_read and stack.valid and stack.prototype.place_result then
      --Redraw arrow
      if dir_indicator ~= nil then rendering.destroy(player.building_direction_arrow) end
      player.building_direction_arrow = rendering.draw_sprite{sprite = "fluid.crude-oil", tint = {r = 0.25, b = 0.25, g = 1.0, a = 0.8}, render_layer = 254, 
         surface = game.get_player(pindex).surface, players = nil, target = player.cursor_pos, orientation = (dir/dirs.east/dirs.south)}
      dir_indicator = player.building_direction_arrow
      rendering.set_visible(dir_indicator,true)
      if players[pindex].hide_cursor or stack.name == "locomotive" or stack.name == "cargo-wagon" or stack.name == "fluid-wagon" or stack.name == "artillery-wagon" then
         rendering.set_visible(dir_indicator,false)
      end
      
      --Redraw footprint
      if player.building_footprint ~= nil then 
         rendering.destroy(player.building_footprint) 
      end
      local width = stack.prototype.place_result.tile_width
      local height = stack.prototype.place_result.tile_height
      local flip = false
      local left_top = {x = math.floor(player.cursor_pos.x),y = math.floor(player.cursor_pos.y)}
      local right_bottom = {x = (left_top.x + width), y = (left_top.y + height)}
      if dir == dirs.east or dir == dirs.west then--Note, does not cover diagonal directions for non-square objects.
         flip = true
      end
      if flip then
         right_bottom = {x = (left_top.x + height), y = (left_top.y + width)}
      end
      if not player.cursor then
         if p_dir == dirs.west and not flip then
            left_top.x = (left_top.x - width + 1)
            right_bottom.x = (right_bottom.x - width + 1)
         elseif p_dir == dirs.west and flip then
            left_top.x = (left_top.x - height + 1)
            right_bottom.x = (right_bottom.x - height + 1)
         elseif p_dir == dirs.north and not flip then
            left_top.y = (left_top.y - height + 1)
            right_bottom.y = (right_bottom.y - height + 1)
         elseif p_dir == dirs.north and flip then
            left_top.y = (left_top.y - width + 1)
            right_bottom.y = (right_bottom.y - width + 1)
         end
      end
      player.building_footprint = rendering.draw_rectangle{left_top = left_top, right_bottom = right_bottom , color = {r = 0.25, b = 0.25, g = 1.0, a = 0.25}, draw_on_ground = true, 
         surface = game.get_player(pindex).surface, players = nil }
      rendering.set_visible(player.building_footprint,true)
      if players[pindex].hide_cursor or stack.name == "locomotive" or stack.name == "cargo-wagon" or stack.name == "fluid-wagon" or stack.name == "artillery-wagon" then
         rendering.set_visible(player.building_footprint,false)
      end
   else
      if dir_indicator ~= nil then rendering.set_visible(dir_indicator,false) end
      if player.building_footprint ~= nil then rendering.set_visible(player.building_footprint,false) end
   end
   
   --Recolor cursor boxes if multiplayer
   if game.is_multiplayer() then
      set_cursor_colors_to_player_colors(pindex)
   end
end

--Highlights the tile or the entity under the cursor
function cursor_highlight(pindex, ent, box_type, skip_mouse_movement)
   local p = game.get_player(pindex)
   local c_pos = players[pindex].cursor_pos
   local h_box = players[pindex].cursor_ent_highlight_box
   local h_tile = players[pindex].cursor_tile_highlight_box
   if c_pos == nil then
      return
   end
   if h_box ~= nil and h_box.valid then
      h_box.destroy()
   end
   if h_tile ~= nil and rendering.is_valid(h_tile) then
      rendering.destroy(h_tile)
   end
   
   if players[pindex].hide_cursor then
      players[pindex].cursor_ent_highlight_box = nil
      players[pindex].cursor_tile_highlight_box = nil
      return
   end
   
   if ent ~= nil and ent.valid and ent.name ~= "highlight-box" and ent.type ~= "flying-text" then
      h_box = p.surface.create_entity{name = "highlight-box", force = "neutral", surface = p.surface, render_player_index = pindex, box_type = "entity", 
         position = c_pos, source = ent}
      if box_type ~= nil then
         h_box.highlight_box_type = box_type
      else
         h_box.highlight_box_type = "entity"
      end
   end
   
   --Highlight the currently focused ground tile.
   h_tile = rendering.draw_rectangle{color = {0.75,1,1,0.75}, surface = p.surface, draw_on_ground = true, players = nil,
      left_top = {math.floor(c_pos.x)+0.05,math.floor(c_pos.y)+0.05}, right_bottom = {math.ceil(c_pos.x)-0.05,math.ceil(c_pos.y)-0.05}}
   
   players[pindex].cursor_ent_highlight_box = h_box
   players[pindex].cursor_tile_highlight_box = h_tile
   game.get_player(pindex).game_view_settings.update_entity_selection = true
   
   --Highlight nearby entities by default means (reposition the cursor)
   if players[pindex].vanilla_mode or skip_mouse_movement == true then
      return 
   end 
   if util.distance(p.position,c_pos) <= game.get_player(pindex).reach_distance then
      move_cursor_map(center_of_tile(c_pos),pindex)
   else
      move_cursor_map(center_of_tile(p.position),pindex)
   end
   
   --Recolor cursor boxes if multiplayer
   if game.is_multiplayer() then
      set_cursor_colors_to_player_colors(pindex)
   end
end

function set_cursor_colors_to_player_colors(pindex)
   if not check_for_player(pindex) then
      return 
   end
   local p = game.get_player(pindex)
   if rendering.is_valid(players[pindex].cursor_tile_highlight_box) then
      rendering.set_color(players[pindex].cursor_tile_highlight_box,p.color)
   end
   if rendering.is_valid(players[pindex].building_footprint) then
      rendering.set_color(players[pindex].building_footprint,p.color)
   end
end

--Draws a sprite over the head of the player, with the selected scale. Set it to nil to clear it.
function update_overhead_sprite(sprite, scale_in, radius_in, pindex)
   local player = players[pindex]
   local p = game.get_player(pindex)
   local scale = scale_in 
   local radius = radius_in 
   
   if player.overhead_circle ~= nil then
      rendering.destroy(player.overhead_circle) 
   end
   if player.overhead_sprite ~= nil then
      rendering.destroy(player.overhead_sprite) 
   end
   if sprite ~= nil then
      player.overhead_circle = rendering.draw_circle{color = {r = 0.2, b = 0.2, g = 0.2, a = 0.9}, radius = radius, draw_on_ground = true,--laterdo figure out render layer blend issue
         surface = p.surface, target = {x = p.position.x, y = p.position.y - 3 - radius}, filled = true}
      rendering.set_visible(player.overhead_circle,true)
      player.overhead_sprite = rendering.draw_sprite{sprite = sprite, x_scale = scale, y_scale = scale,--tint = {r = 0.9, b = 0.9, g = 0.9, a = 1.0},
         surface = p.surface, target = {x = p.position.x, y = p.position.y - 3 - radius}, orientation = dirs.north}
      rendering.set_visible(player.overhead_sprite,true)
   end
end

--Draws a custom GUI with a sprite in the middle of the screen. Set it to nil to clear it.
function update_custom_GUI_sprite(sprite, scale_in, pindex)
   local player = players[pindex]
   local p = game.get_player(pindex)
   local scale = scale_in
   
   if sprite == nil and player.custom_GUI_frame ~= nil and player.custom_GUI_frame.valid then
      player.custom_GUI_frame.visible = false
   else
      local f = player.custom_GUI_frame
      local s1 = player.custom_GUI_sprite
      if f == nil or not f.valid then
         f = game.get_player(pindex).gui.screen.add{type="frame"}
         f.force_auto_center()
         f.bring_to_front()
      end
      if s1 == nil or not s1.valid then
         s1 = f.add{type="sprite",caption = "custom menu"}
      end
      if s1.sprite ~= sprite then 
         s1.sprite = sprite
      end
      f.visible = true
      player.custom_GUI_frame = f
      player.custom_GUI_sprite = s1
      f.bring_to_front()
   end
end

--Alerts a force's players when their structures are destroyed. 300 ticks of cooldown.
script.on_event(defines.events.on_entity_damaged,function(event)
   local ent = event.entity
   local tick = event.tick
   if ent == nil or not ent.valid then
      return
   elseif ent.name == "character" then
      --Check character has any energy shield health remaining
      if ent.player == nil or not ent.player.valid then
         return
      end
      local shield_left = nil
      local armor_inv = ent.player.get_inventory(defines.inventory.character_armor)
      if armor_inv[1] and armor_inv[1].valid_for_read and armor_inv[1].valid and armor_inv[1].grid and armor_inv[1].grid.valid then
         local grid = armor_inv[1].grid
         if grid.shield > 0 then
            shield_left = grid.shield
            --game.print(armor_inv[1].grid.shield,{volume_modifier=0})
         end
      end
      --Play shield and/or character damaged sound
      if shield_left ~= nil then
         ent.player.play_sound{path = "player-shield-damaged",volume_modifier=0.8}
      end
      if shield_left == nil or (shield_left < 1.0 and ent.get_health_ratio() < 1.0) then
         ent.player.play_sound{path = "player-character-damaged",volume_modifier=0.4}
      end
      return
   elseif ent.get_health_ratio() == 1.0 then
      --Ignore alerts if an entity has full health despite being damaged 
      return
   elseif tick < 3600 and tick > 600 then
      --No alerts for the first 10th to 60th seconds (because of the alert spam from spaceship fire damage)
      return
   end
   
   local attacker_force = event.force
   local damaged_force = ent.force
   --Alert all players of the damaged force
   for pindex, player in pairs(players) do
      if players[pindex] ~= nil and game.get_player(pindex).force.name == damaged_force.name 
         and (players[pindex].last_damage_alert_tick == nil or (tick - players[pindex].last_damage_alert_tick) > 300) then
         players[pindex].last_damage_alert_tick = tick
         players[pindex].last_damage_alert_pos = ent.position
         local dist = math.ceil(util.distance(players[pindex].position,ent.position))
         local dir = direction_lookup(get_direction_of_that_from_this(ent.position,players[pindex].position))
         local result = ent.name .. " damaged by " .. attacker_force.name .. " forces at " .. dist .. " " .. dir
         printout(result,pindex)
         --game.get_player(pindex).print(result,{volume_modifier=0})--**
         game.get_player(pindex).play_sound{path = "alert-structure-damaged",volume_modifier=0.3}
      end
   end
end)

--Alerts a force's players when their structures are destroyed. No cooldown.
script.on_event(defines.events.on_entity_died,function(event)
   local ent = event.entity
   local causer = event.cause
   if ent == nil then
      return
   elseif ent.name == "character" then
      return
   end
   local attacker_force = event.force
   local damaged_force = ent.force
   --Alert all players of the damaged force
   for pindex, player in pairs(players) do
      if players[pindex] ~= nil and game.get_player(pindex).force.name == damaged_force.name then
         players[pindex].last_damage_alert_tick = tick
         players[pindex].last_damage_alert_pos = ent.position
         local dist = math.ceil(util.distance(players[pindex].position,ent.position))
         local dir = direction_lookup(get_direction_of_that_from_this(ent.position,players[pindex].position))
         local result = ent.name .. " destroyed by " .. attacker_force.name .. " forces at " .. dist .. " " .. dir
         printout(result,pindex)
         --game.get_player(pindex).print(result,{volume_modifier=0})--**
         game.get_player(pindex).play_sound{path = "utility/alert_destroyed",volume_modifier=0.5}
      end
   end
end)

--Notify all players when a player character dies
script.on_event(defines.events.on_player_died,function(event)
   local pindex = event.player_index
   local p = game.get_player(pindex)
   local causer = event.cause
   local bodies = p.surface.find_entities_filtered{name = "character-corpse"}
   local latest_body = nil
   local latest_death_tick = 0
   local name = p.name
   if name == nil then
      name = " "
   end
   --Find the most recent character corpse
   for i,body in ipairs(bodies) do
      if body.character_corpse_player_index == pindex and body.character_corpse_tick_of_death  > latest_death_tick then
         latest_body = body
         latest_death_tick = latest_body.character_corpse_tick_of_death
      end
   end
   --Verify the latest death
   if event.tick - latest_death_tick > 120 then 
      latest_body = nil
   end
   --Generate death message
   local result = "Player " .. name 
   if causer == nil or not causer.valid then
      result = result .. " died "
   elseif causer.name == "character" and causer.player ~= nil and causer.player.valid then
      local other_name = causer.player.name
      if other_name == nil then
         other_name = ""
      end
      result = result .. " was killed by player " .. other_name
   else
      result = result .. " was killed by " .. causer.name
   end
   if latest_body ~= nil and latest_body.valid then
      result = result .. " at " .. math.floor(0.5+latest_body.position.x) .. ", " .. math.floor(0.5+latest_body.position.y) .. "."
   end
   --Notify all players
   for pindex, player in pairs(players) do
      players[pindex].last_damage_alert_tick = tick
      printout(result,pindex)
      game.get_player(pindex).print(result)--**laterdo unique sound, for now use console sound 
   end
end)

--Allows searching a menu that has support written for this
function menu_search_open(pindex)
   --Only allow "inventory" and "building" menus for now
   if not players[pindex].in_menu then
      printout("This menu does not support searching.",pindex)
      return
   end
   if players[pindex].menu ~= "inventory" and players[pindex].menu ~= "building" and players[pindex].menu ~= "crafting" and players[pindex].menu ~= "technology" then
      printout(players[pindex].menu .. " menu does not support searching.",pindex)
      return
   end
   
   --Open the searchbox frame
   players[pindex].entering_search_term = true
   players[pindex].menu_search_index = 0
   players[pindex].menu_search_index_2 = 0
   local frame = game.get_player(pindex).gui.screen.add{type = "frame", name = "enter-search-term"}
   frame.bring_to_front()
   frame.force_auto_center()
   frame.focus()
   players[pindex].menu_search_frame = frame
   local input = frame.add{type="textfield", name = "input"}
   input.focus()
   
   --Inform the player
   printout(players[pindex].menu .. " enter a search term and press 'ENTER' ",pindex)
end

--Reads out the next inventory/menu item to match the search term
function menu_search_get_next(pindex, str, start_phrase_in)
   --Only allow "inventory" and "building" menus for now
   if not players[pindex].in_menu then
      printout("This menu does not support searching.",pindex)
      return
   end
   if players[pindex].menu ~= "inventory" and players[pindex].menu ~= "building" and players[pindex].menu ~= "crafting" and players[pindex].menu ~= "technology"then
      printout(players[pindex].menu .. " menu does not support searching.",pindex)
      return
   end
   if str == nil or str == "" then
      printout("Missing search term", pindex)
      return 
   end
   --Start phrase
   local start_phrase = ""
   if start_phrase_in ~= nil then
      start_phrase = start_phrase_in
   end
   --Get the current search index
   local search_index = players[pindex].menu_search_index
   local search_index_2 = players[pindex].menu_search_index_2
   if search_index == nil then
      players[pindex].menu_search_index = 0
      players[pindex].menu_search_index_2 = 0
      search_index = 0
      search_index_2 = 0
   end
   --Search for the new index in the appropriate menu
   local inv = nil
   local new_index = nil
   local new_index_2 = nil
   local pb = players[pindex].building 
   if players[pindex].menu == "inventory" then
      inv = game.get_player(pindex).get_main_inventory()
      new_index = inventory_find_index_of_next_name_match(inv, search_index, str, pindex)
   elseif players[pindex].menu == "building" and pb.sectors and pb.sectors[pb.sector] and pb.sectors[pb.sector].name == "Output" then
      inv = game.get_player(pindex).opened.get_output_inventory()
      new_index = inventory_find_index_of_next_name_match(inv, search_index, str, pindex)
   elseif players[pindex].menu == "crafting" then
      new_index, new_index_2 = crafting_find_index_of_next_name_match(str,pindex, search_index, search_index_2, players[pindex].crafting.lua_recipes)
   elseif players[pindex].menu == "building" and pb.recipe_selection == true then
      new_index, new_index_2 = crafting_find_index_of_next_name_match(str,pindex, search_index, search_index_2, players[pindex].building.recipe_list)
   elseif players[pindex].menu == "technology" then
      local techs = {} --Reads the selected tech catagory
      if players[pindex].technology.category == 1 then
         techs = players[pindex].technology.lua_researchable
      elseif players[pindex].technology.category == 2 then
         techs = players[pindex].technology.lua_locked
      elseif players[pindex].technology.category == 3 then
         techs = players[pindex].technology.lua_unlocked
      end
      new_index = inventory_find_index_of_next_name_match(techs, search_index, str, pindex)
   else
      printout("This menu or building sector does not support searching.",pindex)
      return
   end
   --Return a menu output according to the index found 
   if new_index <= 0 then
      printout("Could not find " .. str,pindex)
      game.print("Could not find " .. str,{volume_modifier = 0})
      return
   elseif players[pindex].menu == "inventory" then
      players[pindex].menu_search_index = new_index
      players[pindex].inventory.index = new_index
      read_inventory_slot(pindex, start_phrase)
   elseif players[pindex].menu == "building" and pb.sectors and pb.sectors[pb.sector] and pb.sectors[pb.sector].name == "Output" then
      players[pindex].menu_search_index = new_index
      players[pindex].building.index = new_index
      read_building_slot(pindex,false)
   elseif players[pindex].menu == "crafting" then
      players[pindex].menu_search_index = new_index
      players[pindex].menu_search_index_2 = new_index_2
      players[pindex].crafting.category = new_index
      players[pindex].crafting.index = new_index_2
      read_crafting_slot(pindex, start_phrase)
   elseif players[pindex].menu == "building" and players[pindex].building.recipe_selection == true then
      players[pindex].menu_search_index = new_index
      players[pindex].menu_search_index_2 = new_index_2
      players[pindex].building.category = new_index
      players[pindex].building.index = new_index_2
      read_building_recipe(pindex, start_phrase)
   elseif players[pindex].menu == "technology" then
      local techs = {}
      local note = start_phrase
      if players[pindex].technology.category == 1 then
         techs = players[pindex].technology.lua_researchable
         note = " researchable "
      elseif players[pindex].technology.category == 2 then
         techs = players[pindex].technology.lua_locked
         note = " locked "
      elseif players[pindex].technology.category == 3 then
         techs = players[pindex].technology.lua_unlocked
         note = " unlocked "
      end
      players[pindex].menu_search_index = new_index
      players[pindex].technology.index = new_index
      read_technology_slot(pindex, note)
   else
      printout("Search error",pindex)
      return
   end
end

--Reads out the last inventory/menu item to match the search term
function menu_search_get_last(pindex,str)
   --Only allow "inventory" and "building" menus for now
   if not players[pindex].in_menu then
      printout("This menu does not support searching backwards.",pindex)
      return
   end
   if players[pindex].menu ~= "inventory" and players[pindex].menu ~= "building" then
      printout(players[pindex].menu .. " menu does not support searching backwards.",pindex)
      return
   end
   if str == nil or str == "" then
      printout("Missing search term", pindex)
      return
   end
   --Get the current search index
   local search_index = players[pindex].menu_search_index
   if search_index == nil then
      players[pindex].menu_search_index = 0
      search_index = 0
   end
   --Search for the new index in the appropriate menu
   local inv = nil
   local new_index = nil
   local pb = players[pindex].building
   if players[pindex].menu == "inventory" then
      inv = game.get_player(pindex).get_main_inventory()
      new_index = inventory_find_index_of_last_name_match(inv, search_index, str, pindex)
   elseif players[pindex].menu == "building" and pb.sectors and pb.sectors[pb.sector] and pb.sectors[pb.sector].name == "Output" then
      inv = game.get_player(pindex).opened.get_output_inventory()
      new_index = inventory_find_index_of_last_name_match(inv, search_index, str, pindex)
   else
      printout("This menu or building sector does not support searching backwards.",pindex)
      return
   end
   --Return a menu output according to the index found 
   if new_index <= 0 then
      printout("Could not find " .. str,pindex)
      return
   elseif players[pindex].menu == "inventory" then
      players[pindex].menu_search_index = new_index
      players[pindex].inventory.index = new_index
      read_inventory_slot(pindex)
   elseif players[pindex].menu == "building" and pb.sectors and pb.sectors[pb.sector] and pb.sectors[pb.sector].name == "Output" then
      players[pindex].menu_search_index = new_index
      players[pindex].building.index = new_index
      read_building_slot(pindex,false)
   else
      printout("Search error",pindex)
      return
   end
end

--Returns the index for the next inventory item to match the search term, for any lua inventory
function inventory_find_index_of_next_name_match(inv,index,str,pindex)
   local repeat_i = -1
   if index < 1 then
      index = 1
   end
   --Iterate until the end of the inventory for a match
   for i=index, #inv, 1 do
      local stack = inv[i]
      if stack ~= nil and (stack.object_name == "LuaTechnology" or stack.valid_for_read) then  
         local name = string.lower(localising.get(stack.prototype,pindex))
         local result = string.find(name, str)
         if result ~= nil then 
            if name ~= players[pindex].menu_search_last_name then
               players[pindex].menu_search_last_name = name
               game.get_player(pindex).play_sound{path = "Inventory-Move"}--sound for finding the next
               return i
            else
               repeat_i = i
            end
         end
         --game.print(i .. " : " .. name .. " vs. " .. str,{volume_modifier=0})
      end
   end
   --End of inventory reached, circle back
   game.get_player(pindex).play_sound{path = "player-mine"}--sound for having cicled around 
   for i=1, index, 1 do
      local stack = inv[i]
      if stack ~= nil and (stack.object_name == "LuaTechnology" or stack.valid_for_read) then 
         local name = string.lower(localising.get(stack.prototype,pindex))
         local result = string.find(name, str)
         if result ~= nil then 
            if name ~= players[pindex].menu_search_last_name then
               players[pindex].menu_search_last_name = name
               game.get_player(pindex).play_sound{path = "Inventory-Move"}--sound for finding the next
               return i
            else
               repeat_i = i
            end
         end
         --game.print(i .. " : " .. name .. " vs. " .. str,{volume_modifier=0})
      end 
   end
   --Check if any repeats found
   if repeat_i > 0 then
      return repeat_i
   end
   --No matches found at all
   return -1 
end

--Returns the index for the last inventory item to match the search term, for any lua inventory
function inventory_find_index_of_last_name_match(inv,index,str,pindex)
   local repeat_i = -1
   if index < 1 then
      index = 1
   end
   --Iterate until the start of the inventory for a match
   for i=index, 1, -1 do 
      local stack = inv[i]
      if stack ~= nil and stack.valid_for_read then  
         local name = string.lower(localising.get(stack.prototype,pindex))
         local result = string.find(name, str)
         if result ~= nil then 
            if name ~= players[pindex].menu_search_last_name then
               players[pindex].menu_search_last_name = name
               game.get_player(pindex).play_sound{path = "Inventory-Move"}--sound for finding the next
               return i
            else
               repeat_i = i
            end
         end
         --game.print(i .. " : " .. name .. " vs. " .. str,{volume_modifier=0})
      end
   end
   --Start of inventory reached, circle back
   game.get_player(pindex).play_sound{path = "player-mine"}--sound for having cicled around 
   for i=#inv, index, -1 do
      local stack = inv[i]
      if stack ~= nil and stack.valid_for_read then  
         local name = string.lower(localising.get(stack.prototype,pindex))
         local result = string.find(name, str)
         if result ~= nil then 
            if name ~= players[pindex].menu_search_last_name then
               players[pindex].menu_search_last_name = name
               game.get_player(pindex).play_sound{path = "Inventory-Move"}--sound for finding the next
               return i
            else
               repeat_i = i
            end
         end
         --game.print(i .. " : " .. name .. " vs. " .. str,{volume_modifier=0})
      end
   end
   --Check if any repeats found
   if repeat_i > 0 then
      return repeat_i
   end
   --No matches found at all
   return -1 
end

--Returns the index for the next recipe to match the search term, designed for the way recipes are saved in players[pindex]
function crafting_find_index_of_next_name_match(str,pindex,last_i, last_j, recipe_set)
   local recipes = recipe_set
   local cata_total = #recipes
   local repeat_i = -1
   local repeat_j = -1
   if last_i < 1 then
      last_i = 1
   end
   if last_j < 1 then
      last_j = 1
   end
   --Iterate until the end of the inventory for a match
   for i = last_i, cata_total, 1 do
      for j = last_j, #recipes[i], 1 do 
         local recipe = recipes[i][j]
         if recipe and recipe.valid then
            local name = string.lower(localising.get(recipe,pindex))
            local result = string.find(name, str)
            --game.print(i .. "," .. j .. " : " .. name .. " vs. " .. str,{volume_modifier=0})
            if result ~= nil then 
               --game.print(" * " .. i .. "," .. j .. " : " .. name .. " vs. " .. str .. " * ",{volume_modifier=0})
               if name ~= players[pindex].menu_search_last_name then
                  players[pindex].menu_search_last_name = name
                  game.get_player(pindex).play_sound{path = "Inventory-Move"}--sound for finding the next
                  --game.print(" ** " .. recipes[i][j].name .. " ** ")
                  return i, j
               else
                  repeat_i = i
                  repeat_j = j
               end
            end
         end
      end
      last_j = 1
   end
   --End of inventory reached, circle back
   game.get_player(pindex).play_sound{path = "player-mine"}--sound for having cicled around 
   for i = 1, cata_total, 1 do
      for j = 1, #recipes[i], 1 do 
         local recipe = recipes[i][j]
         if recipe and recipe.valid then
            local name = string.lower(localising.get(recipe,pindex))
            local result = string.find(name, str)
            --game.print(i .. "," .. j .. " : " .. name .. " vs. " .. str,{volume_modifier=0})
            if result ~= nil then 
               --game.print(" * " .. i .. "," .. j .. " : " .. name .. " vs. " .. str .. " * ",{volume_modifier=0})
               if name ~= players[pindex].menu_search_last_name then
                  players[pindex].menu_search_last_name = name
                  game.get_player(pindex).play_sound{path = "Inventory-Move"}--sound for finding the next
                  --game.print(" ** " .. recipes[i][j].name .. " ** ")
                  return i, j
               else
                  repeat_i = i
                  repeat_j = j
               end
            end
         end
      end
   end
   --Check if any repeats found
   if repeat_i > 0 then
      return repeat_i, repeat_j
   end
   --No matches found at all
   return -1, -1 
end

script.on_event(defines.events.on_string_translated,localising.handler)
 
--If the player has unexpected lateral movement while smooth running in a cardinal direction, like from bumping into an entity or being at the edge of water, play a sound.
function check_and_play_bump_alert_sound(pindex,this_tick)
   if not check_for_player(pindex) or players[pindex].menu == "prompt" then
      return 
   end
   local p = game.get_player(pindex)
   local face_dir = p.walking_state.direction
   
   --Initialize 
   if players[pindex].bump == nil then
      reset_bump_stats(pindex)
   end
   
   --Return and reset if in a menu or a vehicle or in a different walking mode than smooth walking
   if players[pindex].in_menu or p.vehicle ~= nil or players[pindex].walk ~= 2 then
      players[pindex].bump.last_pos_4 = nil
      players[pindex].bump.last_pos_3 = nil
      players[pindex].bump.last_pos_2 = nil
      players[pindex].bump.last_pos_1 = nil
      players[pindex].bump.last_dir_2 = nil
      players[pindex].bump.last_dir_1 = nil
      return
   end
   
   --Update Positions and directions since last check
   players[pindex].bump.last_pos_4 = players[pindex].bump.last_pos_3
   players[pindex].bump.last_pos_3 = players[pindex].bump.last_pos_2
   players[pindex].bump.last_pos_2 = players[pindex].bump.last_pos_1
   players[pindex].bump.last_pos_1 = p.position
   
   players[pindex].bump.last_dir_2 = players[pindex].bump.last_dir_1
   players[pindex].bump.last_dir_1 = face_dir
   
   --Return if not walking
   if p.walking_state.walking == false then return end
      
   --Return if not enough positions filled (trying 4 for now)
   if players[pindex].bump.last_pos_4 == nil then return end 
   
   --Return if bump sounded recently
   if this_tick - players[pindex].bump.last_bump_tick < 15 then return end
   
   --Return if player changed direction recently
   if this_tick - players[pindex].bump.last_dir_key_tick < 30 and players[pindex].bump.last_dir_key_1st ~= players[pindex].bump.last_dir_key_2nd then return end
   
   --Return if current running direction is not equal to the last (e.g. letting go of a key)
   if face_dir ~= players[pindex].bump.last_dir_key_1st then return end
   
   --Return if no last key info filled (rare)
   if players[pindex].bump.last_dir_key_1st == nil then return end
   
   --Return if no last dir info filled (rare)
   if players[pindex].bump.last_dir_2 == nil then return end
   
   --Return if not walking in a cardinal direction
   if face_dir ~= dirs.north and face_dir ~= dirs.east and face_dir ~= dirs.south and face_dir ~= dirs.west then return end
   
   --Return if last dir is different
   if players[pindex].bump.last_dir_1 ~= players[pindex].bump.last_dir_2 then return end
   
   --Prepare analysis data
   local TOLERANCE = 0.05
   local was_going_straight = false
   local b = players[pindex].bump
   
   local diff_x1 = b.last_pos_1.x - b.last_pos_2.x
   local diff_x2 = b.last_pos_2.x - b.last_pos_3.x
   local diff_x3 = b.last_pos_3.x - b.last_pos_4.x
      
   local diff_y1 = b.last_pos_1.y - b.last_pos_2.y
   local diff_y2 = b.last_pos_2.y - b.last_pos_3.y
   local diff_y3 = b.last_pos_3.y - b.last_pos_4.y
   
   --Check if earlier movement has been straight
   if players[pindex].bump.last_dir_key_1st == players[pindex].bump.last_dir_key_2nd then
      was_going_straight = true
   else
      if face_dir == dirs.north or face_dir == dirs.south then
         if math.abs(diff_x2) < TOLERANCE and math.abs(diff_x3) < TOLERANCE then
            was_going_straight = true
         end
      elseif face_dir == dirs.east or face_dir == dirs.west then
         if math.abs(diff_y2) < TOLERANCE and math.abs(diff_y3) < TOLERANCE then
            was_going_straight = true
         end
      end
   end
   
   --Return if was not going straight earlier (like was running diagonally, as confirmed by last positions)
   if not was_going_straight then 
      return 
   end
   
   --game.print("checking bump",{volume_modifier=0})--
   
   --Check if latest movement has been straight
   local is_going_straight = false
   if face_dir == dirs.north or face_dir == dirs.south then
      if math.abs(diff_x1) < TOLERANCE then
         is_going_straight = true
      end
   elseif face_dir == dirs.east or face_dir == dirs.west then
      if math.abs(diff_y1) < TOLERANCE then
         is_going_straight = true
      end
   end
   
   --Return if going straight now
   if is_going_straight then 
      return 
   end

   --Now we can confirm that there is a sudden lateral movement
   players[pindex].bump.last_bump_tick = this_tick
   p.play_sound{path = "player-bump-alert"}
   local bump_was_ent = false
   local bump_was_cliff = false
   local bump_was_tile = false
   
   --Check if there is an ent in front of the player
   local found_ent = get_selected_ent(pindex)
   local ent = nil
   if found_ent and found_ent.valid and found_ent.type ~= "resource" and found_ent.type ~= "transport-belt" and found_ent.type ~= "item-entity" and found_ent.type ~= "entity-ghost" and found_ent.type ~= "character" then
      ent = found_ent
   end
   if ent == nil or ent.valid == false then 
      local ents = p.surface.find_entities_filtered{position = p.position, radius = 0.75}
      for i, found_ent in ipairs(ents) do 
         --Ignore ents you can walk through, laterdo better collision checks**
         if found_ent.type ~= "resource" and found_ent.type ~= "transport-belt" and found_ent.type ~= "item-entity" and found_ent.type ~= "entity-ghost" and found_ent.type ~= "character" then
            ent = found_ent
         end
      end
   end
   bump_was_ent = (ent ~= nil and ent.valid)
   
   if bump_was_ent then
      if ent.type == "cliff" then
         p.play_sound{path = "player-bump-slide"}
      else
         p.play_sound{path = "player-bump-trip"}
      end
      --game.print("bump: ent:" .. ent.name,{volume_modifier=0})--
      return
   end
   
   --Check if there is a cliff nearby (the weird size can make it affect the player without being read)
   local ents = p.surface.find_entities_filtered{position = p.position, radius = 2, type = "cliff" }
   bump_was_cliff = (#ents > 0)
   if bump_was_cliff then
      p.play_sound{path = "player-bump-slide"}
      --game.print("bump: cliff",{volume_modifier=0})--
      return
   end
   
   --Check if there is a tile that was bumped into
   local tile = p.surface.get_tile(players[pindex].cursor_pos.x, players[pindex].cursor_pos.y)
   bump_was_tile = (tile ~= nil and tile.valid and tile.collides_with("player-layer"))
   
   if bump_was_tile then
      p.play_sound{path = "player-bump-slide"}
      --game.print("bump: tile:" .. tile.name,{volume_modifier=0})--
      return
   end
   
   --The bump was something else, probably missed it...
   --p.play_sound{path = "player-bump-slide"}
   --game.print("bump: unknown, at " .. p.position.x .. "," .. p.position.y ,{volume_modifier=0})--
   return
end

--If walking but recently position has been unchanged, play alert
function check_and_play_stuck_alert_sound(pindex,this_tick)
   if not check_for_player(pindex) or players[pindex].menu == "prompt" then
      return 
   end
   local p = game.get_player(pindex)
  
   --Initialize 
   if players[pindex].bump == nil then
      reset_bump_stats(pindex)
   end
   
   --Return if in a menu or a vehicle or in a different walking mode than smooth walking
   if players[pindex].in_menu or p.vehicle ~= nil or players[pindex].walk ~= 2 then
      return
   end
      
   --Return if not walking
   if p.walking_state.walking == false then return end
      
   --Return if not enough positions filled (trying 3 for now)
   if players[pindex].bump.last_pos_3 == nil then return end 
     
   --Return if no last dir info filled (rare)
   if players[pindex].bump.last_dir_2 == nil then return end
   
   --Prepare analysis data
   local b = players[pindex].bump
   
   local diff_x1 = b.last_pos_1.x - b.last_pos_2.x
   local diff_x2 = b.last_pos_2.x - b.last_pos_3.x
   --local diff_x3 = b.last_pos_3.x - b.last_pos_4.x
      
   local diff_y1 = b.last_pos_1.y - b.last_pos_2.y
   local diff_y2 = b.last_pos_2.y - b.last_pos_3.y
   --local diff_y3 = b.last_pos_3.y - b.last_pos_4.y
   
   --Check if earlier movement has been straight
   if diff_x1 == 0 and diff_y1 == 0 and diff_x2 == 0 and diff_y2 == 0 then --and diff_x3 == 0 and diff_y3 == 0 then
      p.play_sound{path = "player-bump-stuck-alert"}
   end
   
end

function reset_bump_stats(pindex)
   players[pindex].bump = {
      last_bump_tick = 1,
      last_dir_key_tick = 1,
      last_dir_key_1st = nil,
      last_dir_key_2nd = nil,
      last_pos_1 = nil,
      last_pos_2 = nil,
      last_pos_3 = nil,
      last_pos_4 = nil,
      last_dir_2 = nil,
      last_dir_1 = nil
   }
end
