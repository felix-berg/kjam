pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

#include vec2d.lua
#include body.lua
#include util.lua

local world_scale = 8
local world_size = 128 / world_scale
local world_tl = makevec2d(-world_size, -world_size) / 2
local world_br = makevec2d( world_size,  world_size) / 2

function screen_space(pos)
    return pos * world_scale
end

-- physics entities
local static_bodies = {}
local bodies = {}

-- objects with references to physics bodies
local projectiles = {}
local players = {}

local projectile_mass = 0.15
local projectile_radius = 0.2
function add_projectile(pos, vel)
    local p = make_body(pos, vel, projectile_mass, projectile_radius, PROJECTILE)
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

local player_mass = 4
local player_radius = 0.32
function add_player(pos, vel, playeridx)
    local body = make_body(pos, vel, player_mass, player_radius, PLANET)
    add(players, {
        body = body,
        index = playeridx,
        controldir = makevec2d(0, 0)
    })
    add(bodies, body)
end

local recoil_strength = 1200
local 
function shoot_projectile(player, shootdir)
    if (shootdir.x == 0 and shootdir.y == 0) return

    local body = player.body
    body:add_force(shootdir * (-1200))
    -- offset projectile position by player radius in the shooting direction
    local proj_pos = body.pos + shootdir:unit() * (body.radius * 2.01) 
    add_projectile(proj_pos, body.vel + shootdir * 10)
end

function update_player_controls()
    for _, player in ipairs(players) do
        player.controldir = gamepad_dir(player.index)
        if btnp(controls.x, player.index) then
            shoot_projectile(player, player.controldir)
        end
    end
end

add_player(
    makevec2d(-4, -4), 
    makevec2d(-4, 4), 
    0
)

add(static_bodies, make_body(
    makevec2d(0, 0), 
    makevec2d(0, 0),
    16, 0.8, SUN))

local dt = 1 / 60
function update_bodies()
    -- dynamic bodies attract to static bodies and each other
    for _, body in ipairs(bodies) do 
        for _, static_body in ipairs(static_bodies) do
            body:attract_to(static_body)
        end

        for _, other in ipairs(bodies) do
            if body != other then
                body:attract_to(other)
            end
        end
    end

    for _, body in ipairs(bodies) do
        body:update(dt)
    end
end

function _init()
    camera(-64, -64)
end

function _update60()
    update_player_controls()
    remove_dead_projectiles()
    update_bodies()
end

function _draw() 
    cls()
    for _, v in ipairs(static_bodies) do
        local s = v.pos * world_scale
        local r = v.radius * world_scale
        circ(s.x, s.y, r)
    end
    
    for _, v in ipairs(bodies) do
        local s = v.pos * world_scale
        local r = v.radius * world_scale
        circ(s.x, s.y, r)
    end

    for _, player in ipairs(players) do 
        if player.controldir.x != 0 or player.controldir.y != 0 then 
            local p = player.body.pos * world_scale
            local d = player.controldir:unit() * 0.4 * world_scale
            line(p.x, p.y, p.x + d.x, p.y + d.y)
        end
    end
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000c70000000000000066000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0070070000cbcc000000000000488800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000cbbccc00006600004888440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000ccccbc000aa600008884480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0070070000ccbb0000aa000000484800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000770000a00000000067000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
