pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

#include vec2d.lua
#include body.lua
#include particle.lua
#include util.lua
#include pausescreen.lua

local paused = true

local sounds = {
    projectile = 0,
    sun_swallow = 1,
    planet_explosion = 2,
    planet_explosion_rumble = 3,
    projectile_explosion = 4,
    out_of_bounds_beep = 5,
    round_win = 16,
    game_win_lead = 21,
    game_win_bass = 22,
}

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

local projectile_mass = 1.5
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
    return out_of_bounds(proj.pos, world_tl - (world_br - world_tl) * 0.25, world_br + (world_br - world_tl) * 0.25)
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
    
    local min_dist = radius + body.radius

    local da = 1 / fragment_count
    for i = 1, fragment_count do
        local angle = da * i
        
        angle += random_btwn(-angle_spread, angle_spread)
        dist = min_dist -- random_btwn(min_dist, fragment_max_spawn_distance)

        local angle_vec = makevec2d(cos(angle), sin(angle))
        angle_vec:normalize()

        local pos_offset = angle_vec * dist
        local exp_strength = random_btwn(min_explosion_strength, max_explosion_strength)
        local vel = angle_vec * exp_strength

        add_fragment(body.pos + pos_offset, vel, mass, radius)
    end
end

function explode(body)
    local colors = {5, 5, 8, 8, 9, 9, 10, 10}
    for i = 1, 8 do
        local prange = 2 * body.radius
        local vrange = 5 * body.radius
        local lifetime = random_btwn(body.radius * 100, body.radius * 300)

        local pos = body.pos + makevec2d(random_btwn(-prange, prange), random_btwn(-prange, prange))
        make_particle(PARTICLE_SMOKE, colors[i], pos, makevec2d(random_btwn(-vrange, vrange), random_btwn(-vrange, vrange)), lifetime)
    end
end

function play_collision_sfx(b1, b2)
    if b1.type == SUN or b2.type == SUN then
        sfx(sounds.sun_swallow)
    elseif b1.type == PLANET or b2.type == PLANET then
        sfx(sounds.planet_explosion)
        sfx(sounds.planet_explosion_rumble)
    elseif b1.type == PROJECTILE then
        sfx(sounds.projectile_explosion)
    end
end

function handle_body_collision(b1, b2)
    if (b1.type != SUN) del(bodies, b1)
    if (b2.type != SUN) del(bodies, b2)

    if (b1.type == PLANET and b2.type != SUN) generate_fragments(b1, 3)
    if (b2.type == PLANET and b1.type != SUN) generate_fragments(b2, 3)

    if b1.type == SUN then
        local dir = b2.pos - b1.pos
        local spread = 2
        dir:normalize()
        for i = 1, 16 do
            local vel = dir * random_btwn(4, 11)
            vel += makevec2d(random_btwn(-spread, spread), random_btwn(-spread, spread))
            make_particle(PARTICLE_SPARK, random_btwn(8, 10), b1.pos, vel, 60)
        end
    end

    if b1.type != SUN and b2.type != SUN then
        explode(b1)
        explode(b2)
    end
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
        play_collision_sfx(b1, b2)
        
        local p1 = find_player(b1)
        local p2 = find_player(b2)

        if p1 != nil then p1.alive = false end
        if p2 != nil then p2.alive = false end
    end
end

local player_mass = 6
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
        out_of_bounds_time = 0,
        fg_color = fg_color,
        bg_color = bg_color,
        last_shot_t = 0
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

local shoot_delay = 0.2
local shoot_strength = 6
function shoot_projectile(player, shootdir)
    local now = time()
    printh(now)
    if now - player.last_shot_t < shoot_delay then
        return
    end
    player.last_shot_t = now

    if (shootdir.x == 0 and shootdir.y == 0) return

    local body = player.body
    body:add_force(calculate_recoil(body, shootdir))

    sfx(sounds.projectile)

    -- offset projectile position by player radius in the shooting direction
    local proj_pos = body.pos + shootdir:unit() * (body.radius * 2.01) 
    local vel = shootdir * shoot_strength 
    add_projectile(proj_pos, vel)
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

local out_of_bounds_death_time = 300
function update_out_of_bounds_time(player)
    if out_of_bounds(player.body.pos, world_tl, world_br) then
        player.out_of_bounds_time += 1
    else
        player.out_of_bounds_time = 0
    end
    if player.out_of_bounds_time > out_of_bounds_death_time then
        del(bodies, player.body)
        player.alive = false
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
    elseif level == 4 then
        -- two suns
        
        local sun1 = add_sun(makevec2d( 4, 0), 16, 0.8)
        local sun2 = add_sun(makevec2d(-4, 0), 16, 0.8)

        add_player_body(players[1], makevec2d(-1, -1), makevec2d(-2.2, -3.5), 0)
        add_player_body(players[2], makevec2d(1, 1), makevec2d(2.2, 3.5), 0)
        -- local player2 = add_player(makevec2d( 5,  5), makevec2d(0, 0), 1)
        -- player1.body.vel = tangent_vel(player1.body, sun)
    end
end


function _init()
    camera(-64, -64)
    initialize_pause_screen()

    -- add_player(0, 1)
    -- add_player(1, 1)

    -- init_level(2)
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
            sfx(sounds.game_win_lead)
            sfx(sounds.game_win_bass)
        else
            init_level(4)
        end

        winner = nil

    end
    
    -- i hate it too
    if gameover_t == 30 then
        for _, player in ipairs(players) do
            if player.alive then 
                player.wins += 1
                winner = player;
                sfx(sounds.round_win + winner.wins - 1)
                printh("Winner was player with controller #" .. winner.index)
            end
        end        
    end
end


local prev_num_bodies = 0
function _update60()
    if paused then
        if update_pause_screen() then
            init_level(4)
            paused = false
        end
    else
        update_player_controls()
        remove_dead_projectiles()
        update_collisions()

        -- projectile trails
        for _, body in ipairs(bodies) do
            if body.type == PROJECTILE then
                local dir = body.vel * -0.2
                dir:normalize()
                local spread = 1
                local vel = dir + makevec2d(random_btwn(-spread, spread), random_btwn(-spread, spread))
                make_particle(PARTICLE_SPARK, random_btwn(9, 11), body.pos, vel, random_btwn(10, 16))
            end
        end
    
        local players_alive = 0
        for _, player in ipairs(players) do
            players_alive = player.alive and players_alive + 1 or players_alive
        end

        if players_alive <= 1 then update_endgame() end

        for _, player in ipairs(players) do
            if (player.alive) update_out_of_bounds_time(player)
        end

        update_bodies()
        
        if #bodies != prev_num_bodies then
            printh("World updated, bodies:")
            for _, body in ipairs(bodies) do
                printh(" - Pos: " .. body.pos.x .. ", " .. body.pos.y .. ", radius: " .. body.radius .. ", mass: " .. body.mass .. ", type: " .. body_type_string(body))
            end
            prev_num_bodies = #bodies
        end
    end
    update_particles()
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

    pal(8, player.fg_color)
    pal(2, player.bg_color)

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

    pal()
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
local ob_blink_freq = 30

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

    
    if player.out_of_bounds_time >= 30 and flr(player.out_of_bounds_time / ob_blink_freq) % 2 == 0 then 
        pal(12, 10)
        pal(1, 7)
    else 
        pal(12, player.fg_color)
        pal(1, player.bg_color)
    end

    if player.out_of_bounds_time >= 30 and player.out_of_bounds_time % (ob_blink_freq * 2) == 0 then
        sfx(sounds.out_of_bounds_beep) 
    end


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
    cls()
    fillp()

    if paused then
        draw_pause_screen()
    else
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

        draw_particles()

        -- draw aiming arrows
        for _, player in ipairs(players) do
            if player.alive then
                draw_aiming_arrows(player)
                draw_out_of_bounds_ui(player)
            end
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
4901000012240152301523014230122300f2300c22009220072200622004220032200221002210012100021001210002000020000200002000020000200002000560005600046000360002600016000060000000
0102000026610296102a6202c6202d6202e6302e6302e6302c6202b620296202862026620236201f6101861015610126100e6100a610086100661005610046100361002610026100261002610026100261002610
0003000034650346603366033670306702d6702a67027670266702467022670206601e6601d6601c6601b6601a6501865017650176501665016640166401664016640156401464012640106300d6200961005600
180e00001662016620166201562015620146201362012610126101161010610106100f6100e6100d6100d6100c6100b6100a6100a6100a6100961009610086100761007610066100661006610056100561005650
0003000034620346203363033630306302d6302a63027630266202462022620206201e6201d6101c6101b6101a6101861017610176101661016610166101661016610156101461012610106100d6100961005600
000a00003305000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000180501f050240500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001905020050250500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001a05021050260500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001b05022050270500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001c05023050280502800029000290002900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001500001d0502905024050210501d0501d000000000a0001a0001b0001d0001d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0015000011120111200c1400c14005150051000510029000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0015000011120111200c1400c14005150051000510029000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00140000150501a0501d0502105026050210501d0501c05015050180501a0501c05015050150500e000100001305017050180501a0501f0501a050170501700015050190501a0501c050210501c0501505015050
001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500001567016670126600b6400c630000000000020600000000000000000000001260000000000001d60032650316502465014650006000c60015600136000000000000000000000000000000000000000000
__music__
02 20212244

