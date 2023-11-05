
local sprite_choices = {-- list of available sprite_choices
    { id = 1,  chosen = false },
    { id = 17, chosen = false },
    { id = 33, chosen = false },
    { id = 49, chosen = false }
} 

local UNAVAILABLE_SPRITE = 62
local pause_screen_players = {} 
local num_players = 2

local player_marker_colors = { 8, 12, 11, 14 }
local player_marker_shadow_colors = { 2, 1, 3, 13 }

function initialize_pause_screen()
    for i = 1, num_players do
        add(pause_screen_players, {
            player_index = i - 1,
            choice_index = (i - 1) % #sprite_choices + 1,
            commited = false,
            marker_color = player_marker_colors[i],
            marker_shadow_color = player_marker_shadow_colors[i]
        })
    end
end

function update_pause_screen()
    for _, player in ipairs(pause_screen_players) do
        local choiceidx = player.choice_index

        if btnp(controls.x, player.player_index) then 
            local choice = sprite_choices[choiceidx]
            if not choice.chosen and not player.commited then 
                choice.chosen = true
                player.commited = true
            elseif choice.chosen and player.commited then
                choice.chosen = false
                player.commited = false
            end
        end

        if not player.commited and btnp(controls.up, player.player_index) then
            local idx = choiceidx - 1
            player.choice_index = (idx - 1) % #sprite_choices + 1 -- wrap around
        elseif not player.commited and btnp(controls.down, player.player_index) then
            local idx = choiceidx + 1
            player.choice_index = (idx - 1) % #sprite_choices + 1
        end
    end

    local num_commited = 0
    for _, plr in ipairs(pause_screen_players) do
        if plr.commited then num_commited += 1 end
    end

    if anyone_pressed(controls.o) and num_commited > 1 then
        for i, player in ipairs(pause_screen_players) do
            if player.commited then
                add_player(player.player_index, sprite_choices[player.choice_index].id, player.marker_color, player.marker_shadow_color)
            end
        end
        return true
    else
        return false
    end
end 

local considering_color = 7
local not_considering_color = 7
local picked_color = 9

function draw_pause_screen()
    cls()
    
    cursor(-48, 52)
    print("press ❎ to choose planet")
    cursor(-48, 60)
    print("press 🅾️ to begin")
    
    local slot_width = 128 / (num_players + 1)
    
    local x = -slot_width * (num_players - 1) / 2
    local y = 8

    local box_width = 15
    local box_height = 15

    local topy = y - box_height * ((#sprite_choices + 1) / 2)
    
    for playeridx, player in ipairs(pause_screen_players) do
        
        local leftx = x - box_width / 2
        local rightx = leftx + box_width
        local boty = topy + box_height * (#sprite_choices + 1)
        
        if playeridx == 1 then 
            cursor(leftx - 18, topy - 10)
        end
        
        cursor(leftx + 4, topy - 10)
        print("p" .. player.player_index + 1, 7)

        -- cursor(leftx + 3, topy + box_height * 4 + 3)
        -- print(player_wins[playeridx] .. "★", 10)

        local tlx = leftx 
        local tly = topy

        line(leftx, topy, rightx, topy, not_considering_color)

        for i, sprite in ipairs(sprite_choices) do
            local brx = tlx + box_width
            local bry = tly + box_height
            
            if i == player.choice_index then
                local color = 0
                if player.commited then color = player.marker_color 
                else color = considering_color end 

                rect(tlx, tly, brx, bry, color)
                
                pal(12, player.marker_color)
                pal(1, player.marker_shadow_color)
                spr(61, tlx + 18, tly + 4)
                pal()
            else
                line(tlx, tly + 1, tlx, bry, not_considering_color)
                line(brx, tly + 1, brx, bry, not_considering_color)
                line(tlx, bry, brx, bry, not_considering_color)
            end

            local id = sprite.id
            if sprite.chosen and not (player.commited and player.choice_index == i)  then
                id = UNAVAILABLE_SPRITE
            end

            spr(id, tlx + 4, tly + 4)

            tly += box_height
        end

        x += slot_width
    end
end
