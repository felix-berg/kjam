pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

#include vec2d.lua
#include body.lua
#include util.lua
#include drawstate.lua

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

local projectiles = {}
local projectile_mass = 0.15
local projectile_radius = 0.2
function add_projectile(pos, vel)
    local p = make_body(
        pos, vel, 
        projectile_mass, projectile_radius, 
        PROJECTILE, DYNAMIC,
        make_projectile_draw_state()
    )

    add(bodies, p)
    add(projectiles, {
        body = p
    })
end

function projectile_should_die(proj)
    local p = proj.body.pos
    return p.x < world_tl.x - world_size / 2 or p.x > world_br.x + world_size / 2 or
           p.y < world_tl.y - world_size / 2 or p.y > world_br.y + world_size / 2
end

function remove_dead_projectiles()
   for _, proj in ipairs(projectiles) do
        if projectile_should_die(proj) then 
            del(bodies, proj.body)
            del(projectiles, proj)
        end
   end
end

function add_fragment(pos, vel, mass, radius)
    add(bodies, make_body(
        pos, vel, mass, radius, FRAGMENT, DYNAMIC,
        make_fragment_draw_state()
    ))
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

    printh(body.pos)

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
                printh(i .. " and " .. j .. " collide")
                add(collisions, { first = b1, second = b2 })
            end
        end
    end

    if #collisions  > 0 then printh("Number of collisions: " .. #collisions) end

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
function add_player(pos, vel, playeridx)
    local body = make_body(pos, vel, player_mass, player_radius, PLANET, DYNAMIC)
    add(players, {
        body = body,
        index = playeridx,
        controldir = makevec2d(0, 0),
        xdown = false,
        alive = true
    })
    add(bodies, body)
end

function x_just_pressed(player)
    if btn(controls.x, player.index) then
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

local recoil_strength = 1200
local shoot_strength = 10
function shoot_projectile(player, shootdir)
    if (shootdir.x == 0 and shootdir.y == 0) return

    local body = player.body
    body:add_force(shootdir * (-1200))

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

add_player(
    makevec2d(-4, -4), 
    makevec2d(-4, 4), 
    0
)

add_player(
    makevec2d(4, 4),
    makevec2d(4, -4),
    1
)

add(bodies, make_body(
    makevec2d(0, 0), 
    makevec2d(0, 0),
    16, 0.8, SUN, STATIC))

local dt = 1 / 60
function update_bodies()
    -- dynamic bodies attract to static bodies and each other
    for _, body in ipairs(bodies) do 
        if not body.is_static then 
            for _, other in ipairs(bodies) do
                if body != other then
                    body:attract_to(other)
                end
            end
        end
    end

    for _, body in ipairs(bodies) do
        if (not body.is_static) body:update(dt)
    end
end

function _init()
    camera(-64, -64)
end

local prev_num_bodies = 0
function _update60()
    update_player_controls()
    remove_dead_projectiles()
    update_collisions()


    if #bodies != prev_num_bodies then
        printh("Bodies:")
        for _, body in ipairs(bodies) do
            printh(" - Pos: " .. body.pos.x .. ", " .. body.pos.y .. ", radius: " .. body.radius .. ", mass: " .. body.mass .. ", type: " .. body_type_string(body))
        end
        prev_num_bodies = #bodies
    end

    update_bodies()
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

function _draw() 
    cls()
    fillp()
    palt(0, true)

    for _, body in ipairs(bodies) do
        local s = screen_space(body.pos)
        local r = screen_space(body.radius)
        if body.type == PLANET then
            spr(1, s.x - 3, s.y - 3)
        elseif body.type == SUN then
            draw_sun(s.x, s.y)
        else
            circ(s.x, s.y, r)
        end
    end

    for _, player in ipairs(players) do
        local s = screen_space(player.body.pos)
        local d = screen_space(player.controldir * 0.8)
        if player.controldir.x != 0 and player.controldir.y != 0 then
            sspr(72, 4, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, player.controldir.x < 0, player.controldir.y < 0)
            -- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
        elseif player.controldir.x != 0 then
            sspr(72, 0, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, player.controldir.x < 0)
            -- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
        elseif player.controldir.y != 0 then
            sspr(72, 0, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, false, player.controldir.y < 0)
            -- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
        end
    end
end

__gfx__
000000000000000000c7c00000000000000000000280000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000c7cc000cccc30000000000000000000028200200000000000000000000000000000000000000000000000000000000000000000000000000000000
0070070003ccc3c033cc333000000000000000000028822800000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000033c3330333c33c000000000000000000280088000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007700003cc33c0c3ccc3c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000cccc3c003cccc0000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000c77c0000c7700000000000000000000028000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000288000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000002228000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000088888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000022882200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00000000009999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000099944900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000094499900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000044994400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000044444400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000004444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
