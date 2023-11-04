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

local static_bodies = {}
local bodies = {}
local projectiles = {}

bodies[1] = make_body(
    makevec2d(-4, -4), 
    makevec2d(-4,  4), 
    4, 0.32)

static_bodies[1] = make_body(
    makevec2d(0, 0), 
    makevec2d(0, 0),
    16, 0.8)

function gamepad_dir()
    local v = makevec2d(0, 0)
    if btn(controls.left) then v.x += -1 end
    if btn(controls.right) then v.x += 1 end
    if btn(controls.down) then v.y += 1 end
    if btn(controls.up) then v.y += -1 end
    if v.x == 0 and v.y == 0 then return v end
    return v:unit()
end

function _init()
    camera(-64, -64)
end

local dt = 1 / 60
function _update60()
    for b, body in ipairs(bodies) do
        for o, other in ipairs(bodies) do
            if b != o then 
                body:attract_to(other)
            end
        end

        for o, other in ipairs(static_bodies) do
            body:attract_to(other)
        end

        body:update(dt)
    end

    local control_dir = gamepad_dir()
    if btnp(controls.x) then
        if control_dir.x != 0 or control_dir.y != 0 then
            bodies[1]:add_force(control_dir * (-400))
            projectiles[#projectiles + 1] = make_body(
                bodies[1].pos, control_dir * 0.1, 0, 0.1
            )
        end
    end

    for i, proj in ipairs(projectiles) do
        proj.pos += proj.vel
        if proj.pos.x < world_tl.x or
           proj.pos.y < world_tl.y or
           proj.pos.x > world_br.x or
           proj.pos.y > world_br.y then 
            deli(projectiles, i)
        end
    end
end

function _draw() 
    cls()
    for _, v in ipairs(static_bodies) do
        local s = v.pos * world_scale
        local r = v.radius * world_scale
        circfill(s.x, s.y, r)
    end
    
    for _, v in ipairs(bodies) do
        local s = v.pos * world_scale
        local r = v.radius * world_scale
        circfill(s.x, s.y, r)
    end

    for _, p in ipairs(projectiles) do
        local s = p.pos * world_scale
        local r = p.radius * world_scale
        circfill(s.x, s.y, r)
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
