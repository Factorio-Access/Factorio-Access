
for name, proto in pairs(data.raw.item) do
   local pr = proto.place_result
   local pr_name = ""
   if pr then
      ---@diagnostic disable: undefined-field
      if pr.name then
         pr_name = pr.name
      end
      if not proto.localised_description then
         proto.localised_description = { "entity-description." .. pr_name }
      end
      if not proto.localised_name then
         proto.localised_name = { "entity-name." .. pr_name }
      end
   end
end

for name, proto in pairs(data.raw.container) do
   proto.open_sound  = proto.open_sound  or { filename = "__base__/sound/metallic-chest-open.ogg" , volume = 0.43 }
   proto.close_sound = proto.close_sound or { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.43 }
end

data.raw.character.character.has_belt_immunity = true

for _,item in pairs(vanilla_tip_and_tricks_item_table) do
   remove_tip_and_tricks_item(item);
end

--Modifications to Kruise Kontrol inputs 
local alt_input =
{
  name = "klient-alt-move-to",
  type = "custom-input",
  key_sequence = "CONTROL + ALT + RIGHTBRACKET",
  consuming = "game-only"
}
local cancel_enter =
{
  name = "klient-cancel-enter",
  type = "custom-input",
  linked_game_control = "toggle-driving",
  consuming = "none",
  key_sequence = ""
}
data:extend{alt_input, cancel_enter}

--Modifications to Pavement Driving Assist Continued inputs
data:extend({
    {
        type = "custom-input",
        name = "toggle_drive_assistant",
        key_sequence = "L",
        consuming = "game-only"
    },
    {
        type = "custom-input",
        name = "toggle_cruise_control",
        key_sequence = "O",
        consuming = "game-only"
    },
    {
        type = "custom-input",
        name = "set_cruise_control_limit",
        key_sequence = "CONTROL + O",
        consuming = "game-only"
    },
    {
        type = "custom-input",
        name = "confirm_set_cruise_control_limit",
        key_sequence = "",
        linked_game_control = "confirm-gui"
    },
})

--Modify base prototypes to remove their default descriptions 
for name, pack in pairs(data.raw.tool) do 
   if pack.localised_description and pack.localised_description[1] == "item-description.science-pack" then 
      pack.localised_description = nil 
   end
end

for name, mod in pairs(data.raw.module) do 
   if mod.localised_description and mod.localised_description[1] == "item-description.effectivity-module" 
   or mod.localised_description and mod.localised_description[1] == "item-description.productivity-module"
   or mod.localised_description and mod.localised_description[1] == "item-description.speed-module" then 
      mod.localised_description = nil 
   end
end 
 