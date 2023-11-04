pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

#include vec2d.lua
#include body.lua
#include util.lua
#include pausescreen.lua

local paused = true

local world_scale = 8
local world_size = 128 / world_scale
local world_tl = makevec2d(-world_size, -world_size) / 2
local world_br = makevec2d( world_size,  world_size) / 2

function screen_space(pos)
    return pos * world_scale
end

-- physics entities
local bodies = {}

-- objects with references to physics bodies
local players = {}

local projectile_mass = 0.1
local projectile_radius = 0.2
function add_projectile(pos, vel)
    local p = make_body(pos)
    p.vel = vel:copy()
    p.mass = projectile_mass
    p.radius = projectile_radius
    p.type = PROJECTILE
    p.is_static = DYNAMIC
    p.sprite = 5

    add(bodies, p)
end

function out_of_bounds(pos, tl, br)
    return pos.x < tl.x or pos.x > br.x or pos.y < tl.y or pos.y > br.y
end

function projectile_should_die(proj)
    return out_of_bounds(proj.pos, world_tl - makevec2d(1, 1), world_br + makevec2d(1, 1))
end

function remove_dead_projectiles()
   for _, body in ipairs(bodies) do
        if body.type == PROJECTILE and projectile_should_die(body) then 
            del(bodies, body)
        end
   end
end


function add_fragment(pos, vel, mass, radius)
    local fragment_body = make_body(pos)
    fragment_body.vel = vel:copy()
    fragment_body.mass = mass
    fragment_body.radius = radius
    fragment_body.type = FRAGMENT
    fragment_body.is_static = DYNAMIC
    fragment_body.sprite = 5
    add(bodies, fragment_body)
end

local fragment_max_spawn_distance = 2
local min_explosion_strength = 1
local max_explosion_strength = 3
local angle_spread = 0.1
local mass_falloff = 100
local radius_multiplier = 0.1

-- add exploding fragments of this body exploding into the "bodies" table
function generate_fragments(body, fragment_count)
    -- each fragment has a nth size and radius
    local mass = body.mass / (fragment_count * mass_falloff)
    local radius = radius_multiplier * body.radius / fragment_count 
    
    local min_dist = radius

    local da = 1 / fragment_count
    for i = 1, fragment_count do
        local angle = da * i
        
        angle += random_btwn(-angle_spread, angle_spread)
        dist = random_btwn(min_dist, fragment_max_spawn_distance)

        local angle_vec = makevec2d(cos(angle), sin(angle))
        angle_vec:normalize()

        local pos_offset = angle_vec * dist
        local exp_strength = random_btwn(min_explosion_strength, max_explosion_strength)
        local vel = angle_vec * exp_strength

        add_fragment(body.pos + pos_offset, vel, mass, radius)
    end
end

function handle_body_collision(b1, b2)
    if (b1.type != SUN) del(bodies, b1)
    if (b2.type != SUN) del(bodies, b2)

    if (b1.type == PLANET and b2.type != SUN) generate_fragments(b1, 3)
    if (b2.type == PLANET and b1.type != SUN) generate_fragments(b2, 3)
end

function find_player(body)
    for _, player in ipairs(players) do
        if player.body == body then
            return player
        end
    end
    return nil
end

function update_collisions()
    local collisions = {}
    
    for i = 1, #bodies do
        local b1 = bodies[i]
        for j = i + 1, #bodies do 
            local b2 = bodies[j]

            if collides(b1, b2) then 
                add(collisions, { first = b1, second = b2 })
            end
        end
    end

    for _, pair in ipairs(collisions) do
        local b1 = pair.first
        local b2 = pair.second

        handle_body_collision(b1, b2)
            
        local p1 = find_player(b1)
        local p2 = find_player(b2)

        if p1 != nil then p1.alive = false end
        if p2 != nil then p2.alive = false end
    end
end

local player_mass = 4
local player_radius = 0.32
function add_player_body(player, pos, vel)
    local body = make_body(pos)
    body.vel = vel:copy()
    body.mass = player_mass
    body.radius = player_radius
    body.type = PLANET
    body.is_static = false
    body.sprite = player.sprite

    player.body = body

    add(bodies, body)

    return body
end

function add_player(playeridx, sprite, fg_color, bg_color)
    local player = {
        body = nil,
        index = playeridx,
        controldir = makevec2d(0, 0),
        xdown = false,
        sprite = sprite,
        alive = true,
        wins = 0,
        fg_color = fg_color,
        bg_color = bg_color
    }

    add(players, player)

    return player
end

function add_planet(pos, mass, radius)
    local body = make_body(pos)
    body.mass = mass
    body.radius = radius
    body.type = PLANET
    body.is_static = DYNAMIC
    body.sprite = 1
    add(bodies, body)

    return body
end

function add_sun(pos, mass, radius)
    local body = make_body(pos)
    body.mass = mass
    body.radius = radius
    body.type = SUN
    body.is_static = STATIC
    body.sprite = 0
    add(bodies, body)

    return body
end

function x_just_pressed(player)
    if btn(controls.x, player.index) or btn(controls.o, player.index) then
        if player.xdown then return false
        else 
            player.xdown = true
            return true
        end
    else 
        player.xdown = false
        return false
    end
end

local recoil_strength = 240
function calculate_recoil(body, shootdir)
    local u = body.vel:unit() * -1
    local v = shootdir:unit()
    local dot = u.x * v.x + u.y * v.y
    local braking_coefficient = -2.5 * dot + 3.5
    return -recoil_strength * v * braking_coefficient
end

local shoot_strength = 5
function shoot_projectile(player, shootdir)
    if (shootdir.x == 0 and shootdir.y == 0) return

    local body = player.body
    body:add_force(calculate_recoil(body, shootdir))

    -- offset projectile position by player radius in the shooting direction
    local proj_pos = body.pos + shootdir:unit() * (body.radius * 2.01) 
    add_projectile(proj_pos, body.vel + shootdir * shoot_strength)
end

function update_player_controls()
    for _, player in ipairs(players) do
        if player.alive then
            player.controldir = gamepad_dir(player.index)
            if x_just_pressed(player) then
                shoot_projectile(player, player.controldir)
            end
        end
    end
end

local dt = 1 / 60
function update_bodies()
    -- dynamic bodies attract to static bodies and each other
    for _, body in ipairs(bodies) do 
        if not body.is_static then 
            for _, other in ipairs(bodies) do
                if body != other and other.type != PROJECTILE then
                    body:attract_to(other)
                end
            end
        end
    end

    for _, body in ipairs(bodies) do
        if (not body.is_static) body:update(dt)
    end
end

function init_level(level)
    bodies = {}

    for i, player in ipairs(players) do
        player.alive = true
    end

    if level == 1 then
        -- two planets
        local b1 = add_player_body(players[1], makevec2d(-4, -4), makevec2d(0, 0))
        local b2 = add_player_body(players[2], makevec2d( 4,  4), makevec2d(0, 0))
        b1.vel = tangent_vel(b1, b2)
        b2.vel = tangent_vel(b2, b1)
    elseif level == 2 then
        -- sun and two planets
        
        local sun = add_sun(makevec2d(0, 0), 16, 0.8)

        local b1 = add_player_body(players[1], makevec2d(-4, -4), makevec2d(0, 0))
        local b2 = add_player_body(players[2], makevec2d( 4,  4), makevec2d(0, 0))
        b1.vel = tangent_vel(b1, sun)
        b2.vel = tangent_vel(b2, sun)
    elseif level == 3 then
        -- sun, mercury and two planets
        
        local sun = add_sun(makevec2d(0, 0), 16, 0.8)

        local mercury = add_planet(makevec2d(0, -2), 0.2, 0.2)
        mercury.vel = tangent_vel(mercury, sun)
        mercury.sprite = 33

        local b1 = add_player_body(players[1], makevec2d(-5, -5), makevec2d(0, 0))
        local b2 = add_player_body(players[2], makevec2d( 5,  5), makevec2d(0, 0))
        b1.vel = tangent_vel(b1, sun)
        b2.vel = tangent_vel(b2, sun)
    -- elseif level == 4 then
    --     -- two suns
        
    --     local sun1 = add_sun(makevec2d( 4, 0), 16, 0.8)
    --     local sun2 = add_sun(makevec2d(-4, 0), 16, 0.8)

    --     local player1 = add_player(makevec2d(0, 0), makevec2d(5, 6), 0)
    --     -- local player2 = add_player(makevec2d( 5,  5), makevec2d(0, 0), 1)
    --     -- player1.body.vel = tangent_vel(player1.body, sun)
    end
end


function _init()
    camera(-64, -64)
    initialize_pause_screen()
end

local gameover_t = 0
local winner = nil
local new_level = false
local max_wins = 5

function update_endgame()
    gameover_t += 1
    if gameover_t > 60 then
        -- next round
        gameover_t = 0
        
        if winner != nil and winner.wins >= max_wins then
            paused = true
            players = {}
        else
            init_level(flr(rnd(3)) + 1)
        end

        winner = nil

    end
    
    -- i hate it too
    if gameover_t == 30 then
        for _, player in ipairs(players) do
            if player.alive then 
                player.wins += 1
                winner = player;
                printh("Winner was player with controller #" .. winner.index)
            end
        end        
    end
end


local prev_num_bodies = 0
function _update60()
    if paused then
        if update_pause_screen() then
            init_level(flr(rnd(3)) + 1)
            paused = false
        end
    else
        update_player_controls()
        remove_dead_projectiles()
        update_collisions()
    
        local players_alive = 0
        for _, player in ipairs(players) do
            players_alive = player.alive and players_alive + 1 or players_alive
        end

        if players_alive <= 1 then update_endgame() end

        if #bodies != prev_num_bodies then
            printh("World updated, bodies:")
            for _, body in ipairs(bodies) do
                printh(" - Pos: " .. body.pos.x .. ", " .. body.pos.y .. ", radius: " .. body.radius .. ", mass: " .. body.mass .. ", type: " .. body_type_string(body))
            end
            prev_num_bodies = #bodies
        end
    
        update_bodies()
    end
end

---draw---

function draw_sun(x, y)
    for i = -7, 7 do
        for j = -7, 7 do
            local dist = sqrt(i * i + j * j)
            local angle = atan2(j, i)
            if dist < 5 then
                pset(x + i, y + j, 10)
            elseif dist < 6 then
                pset(x + i, y + j, 9)
            elseif dist < 8 + 1.5 * sin(4.5 * angle + 0.2 * time()) then
                pset(x + i, y + j, 8)
            end
        end
    end
end

local diagonal_proj = 21
local vertical_proj = 22
local horizontal_proj = 23
function draw_projectile(body)
    local dir = body.vel:unit()

    local cx = nil
    local cy = nil
    local closest_dot = -20000
    for x = -1, 1 do
        for y = -1, 1 do 
            if x != 0 or y != 0 then
                local u = makevec2d(x, y):unit()
                local dot = dir.x * u.x + dir.y * u.y
                if dot > closest_dot then
                    cx = x
                    cy = y
                    closest_dot = dot
                end
            end
        end
    end

    local sprite = 1
    if abs(cx) == abs(cy) then sprite = diagonal_proj 
    elseif abs(cx) > abs(cy) then sprite = horizontal_proj
    else sprite = vertical_proj end

    local s = screen_space(body.pos)
    spr(sprite, s.x - 2.5, s.y - 2.5, 
        0.5, 0.5, cx < 0, cy > 0)
end

function draw_aiming_arrows(player)
    local s = screen_space(player.body.pos)
    local d = screen_space(player.controldir * 0.8)
    if player.controldir.x != 0 and player.controldir.y != 0 then
        sspr(72, 4, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, player.controldir.x < 0, player.controldir.y < 0)
        -- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
    elseif player.controldir.x != 0 then
        sspr(72, 0, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, player.controldir.x < 0)
        -- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
    elseif player.controldir.y != 0 then
        sspr(76, 0, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, false, player.controldir.y < 0)
        -- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
    end
end

function integer_digits(num)
    local count = 0
    num = flr(num)
    while num != 0 do
        num -= num % 10
        num /= 10
        count += 1
    end
    return count
end

local diagonal_ob_arrow_x = 88
local diagonal_ob_arrow_y = 24
local vertical_ob_arrow_x = 96
local vertical_ob_arrow_y = 24
local horizontal_ob_arrow_x = 104
local horizontal_ob_arrow_y = 24

function draw_out_of_bounds_ui(player)
    if not out_of_bounds(player.body.pos, world_tl, world_br) then return end

    local px = player.body.pos.x
    local py = player.body.pos.y
    local spritex = 0 
    local spritey = 0 

    local sprite_size = 8
    local wl_sprite_size = sprite_size / world_scale

    if px > world_tl.x and px < world_br.x then -- vertical
        spritex = vertical_ob_arrow_x
        spritey = vertical_ob_arrow_y
    elseif py > world_tl.y and py < world_br.y then --horizontal
        spritex = horizontal_ob_arrow_x
        spritey = horizontal_ob_arrow_y
    else -- diagonal
        spritex = diagonal_ob_arrow_x
        spritey = diagonal_ob_arrow_y
    end

    local w = wl_sprite_size / 2
    if     px < world_tl.x + w then px = world_tl.x + w
    elseif px > world_br.x - w then px = world_br.x - w end
    if     py < world_tl.y + w then py = world_tl.y + w
    elseif py > world_br.y - w then py = world_br.y - w end

    
    
    local dist = (makevec2d(px, py) - player.body.pos):size()
    local max_dist = 48
    local sz = ceil(map(clamp(dist, 0, max_dist), 0, max_dist, 8, 3))

    local c = screen_space(makevec2d(px, py))
    local s = c - makevec2d(sz, sz) / 2

    pal(12, player.fg_color)
    pal(1, player.bg_color)
    sspr(spritex, spritey, 8, 8, s.x, s.y, sz, sz, px > 0, py > 0)
    pal()
end

function draw_winner()
    assert(winner != nil)

    local star_width = 6
    
    local lx = screen_space(winner.body.pos.x) - (winner.wins / 2) * star_width
    local y = screen_space(winner.body.pos.y) - 7
    lx += 1
    for i = 1, winner.wins do
        spr(13, lx, y)
        lx += star_width
    end
end

function _draw()
    if paused then
        draw_pause_screen()
    else
        cls(1)
        fillp()
        palt(0, true)

        -- draw bodies
        for _, body in ipairs(bodies) do
            local s = screen_space(body.pos)
            local r = screen_space(body.radius)
            if body.type == PLANET or body.type == FRAGMENT then
                if fget(body.sprite, 0) then -- fragment sprite flag
                    local tile = flr(body.rand * 4)
                    local tile_x = tile % 2
                    local tile_y = flr(tile / 2)
                    sspr(body.sprite * 8 + tile_x * 4, flr(body.sprite / 16) + tile_y * 4, 4, 4, s.x - 3, s.y - 3)
                else
                    spr(body.sprite, s.x - 3, s.y - 3)
                end
            elseif body.type == PROJECTILE then
                draw_projectile(body)
            elseif body.type == SUN then
                draw_sun(s.x, s.y)
            else
                circ(s.x, s.y, r)
            end
        end

        -- draw aiming arrows
        for _, player in ipairs(players) do
            draw_aiming_arrows(player)
            draw_out_of_bounds_ui(player)
        end

        -- draw stars above winner
        if winner != nil then
            draw_winner()
        end


    end
end

__gfx__
0000000000000000000000000000000000000000003c00cc0000000000000000000000000280000000000000000000000000000000a000000000000000000000
0000000000c7cc00000000000000000000000000dccd03cd00000000000000000000000000282002000000000000000000000000aaaaa0000000000000000000
0070070003ccc3c00000000000000000000000000dd00dc0000000000000000000000000002882280000000000000000000000000aaa00000000000000000000
00077000033c333000000000000000000000000000000dd0000000000000000000000000028008800000000000000000000000000a0a00000000000000000000
0007700003cc33c0000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000cccc3c0000000000000000000000000cc00d3c000000000000000000000000000020000000000000000000000000000000000000000000000000000
0000000000c77c00000000000000000000000000d3c00dcd00000000000000000000000000280000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000ddd00d000000000000000000000000002880000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000066000006600000000000000000000000000000000000000000000000000000000000000000000000000000
00000000002228000000000000000000000000000a660000066000000a6600000000000000000000000000000000000000000000000000000000000000000000
00000000088888800000000000000000000000000aa000000aa00000aa6600000000000000000000000000000000000000000000000000000000000000000000
0000000002288220000000000000000000000000a00000000a000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000088822800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000028888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000002288000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000006666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000d6d6d600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000dd666d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000dd6d6600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000dddd6600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000dd66000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000099990000000000000000000000000000000000000000000000000000000000000000000000000000ccc100000cc0000000c1000006600000000000
00000000099944900000000000000000000000000000000000000000000000000000000000000000000000000ccc100000cccc00000cc1000060060000000000
00000000094499900000000000000000000000000000000000000000000000000000000000000000000000000cc100000cccccc000ccc1000606006000000000
00000000044994400000000000000000000000000000000000000000000000000000000000000000000000000c1000000111111000ccc1000600606000000000
00000000044444400000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000cc1000060060000000000
000000000044440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c1000006600000000000
__gff__
0000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
