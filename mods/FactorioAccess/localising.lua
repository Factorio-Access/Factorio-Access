--Here: localisation functions, including event handlers
local localising = {}
--Returns the localised name of an object as a string
function localising.get(object,pindex)--*** todo make this work
   if object.valid and string.sub(object.object_name,-9) ~= "Prototype" then
      object = object.prototype
   end
   local result = players[pindex].localisations
   result = result and result[object.object_name]
   result = result and result[object.name]
   --for debugging
   if not result then
      --game.print("translation fallback for " .. object.object_name .. " " .. object.name )
   end
   result = result or object.name
   return result
end

function localising.request_localisation(thing,pindex)
   local id = game.players[pindex].request_translation(thing.localised_name)
   local lookup=players[pindex].translation_id_lookup
   lookup[id]={thing.object_name,thing.name}
end

function localising.request_all_the_translations(pindex)
   for _, cat in pairs({"entity",
      "item",
      "fluid",
      "tile",
      "equipment",
      "damage",
      "virtual_signal",
      "recipe",
      "technology",
      "decorative",
      "autoplace_control",
      "mod_setting",
      "custom_input",
      "ammo_category",
      "item_group",
      "fuel_category",
      "achievement",
      "equipment_category",
      "shortcut"}) do
      for _, proto in pairs(game[cat.."_prototypes"]) do
         localising.request_localisation(proto,pindex)
      end
   end
end

--Populates the appropriate localised string arrays for every translation
function localising.handler(event)
   local pindex = event.player_index
   local player=players[pindex]
   local successful = event.translated
   local translated_thing=player.translation_id_lookup[event.id]
   if not translated_thing then
      return
   end
   player.translation_id_lookup[event.id] = nil
   if not successful then
      if players[pindex].translation_issue_counter == nil then 
         players[pindex].translation_issue_counter = 1
      else
         players[pindex].translation_issue_counter = players[pindex].translation_issue_counter + 1
      end
      print("translation request ".. event.id .. " failed, request: [" .. serpent.line(event.localised_string) ..  "] for:" .. translated_thing[1] .. ":" .. translated_thing[2] .. ", total issues: " .. players[pindex].translation_issue_counter)
      return
   end
   local localised = players[pindex].localisations
   localised[translated_thing[1]] = localised[translated_thing[1]] or {}
   local translated_list = localised[translated_thing[1]]
   translated_list[ translated_thing[2] ] = event.result
end


return localising