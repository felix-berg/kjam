pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

local vecmt = {}
vecmt.__index = vecmt;

function makevec2d(x, y)
    local v = {
        x = x,
        y = y
    }

    setmetatable(v, vecmt)
    return v 
end

function vecmt.__add(self, other)
    if type(other) ~= "table" or getmetatable(other) ~= vecmt then
        assert(false, "Invalid vecmt add")
    end

    return makevec2d(
        self.x + other.x, 
        self.y + other.y
    )
end

function vecmt.__sub(self, other)
    if type(other) ~= "table" or getmetatable(other) ~= vecmt then
        assert(false, "Invalid vecmt sub")
    end

    return makevec2d(
        self.x - other.x,
        self.y - other.y
    )
end

function vecmt.__mul(a, b)
    if type(a) == "number" then
        return makevec2d(
            b.x * a,
            b.y * a
        )
    elseif type(b) == "number" then
        return makevec2d(
            a.x * b,
            a.y * b
        )
    else
        assert(false, "Can only multiply vector by a number")
    end
end

function vecmt.__div(a, b)
    if type(a) == "number" then
        return makevec2d(
            b.x / a,
            b.y / a
        )
    elseif type(b) == "number" then
        return makevec2d(
            a.x / b,
            a.y / b
        )
    else
        assert(false, "Can only divide vector by a number")
    end
end

function vecmt:addv(other)
    if type(other) ~= "table" or getmetatable(other) ~= vecmt then
        assert(false, "Invalid vecmt add")
    end

    self.x += other.x
    self.y += other.y
end

function vecmt:subv(other)
    if type(other) ~= "table" or getmetatable(other) ~= vecmt then
        assert(false, "Invalid vecmt sub")
    end
    
    self.x -= other.x
    self.y -= other.y
end

function vecmt:mul(scalar)
    if type(scalar) ~= "number" then
        assert(false, "vecmt:mul error: can only multiply by a number")
    end

    self.x *= scalar
    self.y *= scalar
end

function vecmt:div(scalar)
    if type(scalar) ~= "number" then
        assert(false, "vecmt:mul error: can only multiply by a number")
    end

    self.x /= scalar
    self.y /= scalar
end

function vecmt:__tostring()
    return self.x .. ", " .. self.y
end

function vecmt:sizesq()
    return self.x * self.x + self.y * self.y
end

function vecmt:size()
    return sqrt(self:sizesq())
end

function vecmt:unit()
    return self / self:size()
end

function vecmt:set_size(s)
    self:mul(s / self:size())
end

function vecmt:normalize()
    self:div(self:size())
end

function vecmt:limit(l)
    assert(type(l) == "number")

    if self:size() > l then 
        self:set_size(l)
    end
end

local screen = {
    width = 128,
    height = 128
}

local controls = {
    left = ⬅️,
    right = ➡️,
    up = ⬆️,
    down = ⬇️,
    x = ❎,
    o = 🅾️
}

local bodymt = {}
bodymt.__index = bodymt;

function make_body(x, y, vx, vy, mass, radius)
    local sb = {
        pos = makevec2d(x, y),
        vel = makevec2d(vx, vy),
        mass = mass,
        radius = radius 
    }

    setmetatable(sb, bodymt)
    return sb
end

local gravity_constant = 1
function attraction_force(p1, m1, p2, m2)
    local dist_sq = (p1 - p2):sizesq()
    local force = gravity_constant * (m1 * m2 / dist_sq)
    return force
end

function bodymt:attract(pos, mass)
    local f = attraction_force(pos, mass, self.pos, self.mass)
    local d = self.pos - pos
    d:set_size(f)
    return d
end

function lerp(t, min, max)
    return t * (max - min) + min
end

function map(val, old_min, old_max, min, max)
    local t = ((val - old_min) / (old_max - old_min))
    return lerp(t, min, max)
end

local world = {
    bl = makevec2d(-1, -1),
    size = makevec2d(2, 2)
}

function screen_space(pos)
    return makevec2d(
        map(pos.x, world.bl.x, world.bl.x + world.size.x, 0, screen.width),
        map(pos.y, world.bl.y + world.size.y, world.bl.y, 0, screen.height)
    )
end

function screen_space_scale(val)
    return map(val, 0, world.size.x, 0, screen.width)
end

local static_bodies = {}
local bodies = {}
local projectiles = {}

bodies[1] = make_body(-0.5, -0.5, -1, 1, 0.5, 0.048)
static_bodies[1] = make_body(0, 0, 0, 0, 2, 0.1)

function get_control_direction()
    local v = makevec2d(0, 0)
    if btn(controls.left) then v.x = -1 end
    if btn(controls.right) then v.x += 1 end
    if btn(controls.down) then v.y = -1 end
    if btn(controls.up) then v.y += 1 end
    if v.x == 0 and v.y == 0 then return v end
    return v:unit()
end

local dt = 1 / 200
function _update60()
    for b, body in ipairs(bodies) do
        for o, other in ipairs(bodies) do
            if b != o then 
                local v = other:attract(body.pos, body.mass)
                body.vel += (v / body.mass) * dt
                body.pos += body.vel * dt
            end
        end

        for o, other in ipairs(static_bodies) do
            local v = other:attract(body.pos, body.mass)
            body.vel += (v / body.mass) * dt
            body.pos += body.vel * dt
        end
    end

    local control_dir = get_control_direction()

    if btnp(controls.x) then
        if control_dir.x != 0 or control_dir.y != 0 then
            bodies[1].vel -= control_dir
            projectiles[#projectiles + 1] = make_body(
                bodies[1].pos.x, bodies[1].pos.y, 
                control_dir.x * 0.01, control_dir.y * 0.01, 
                0, 0.001
            )
        end
    end

    for i, proj in ipairs(projectiles) do
        proj.pos += proj.vel
        if proj.pos.x < world.bl.x then 
            deli(projectiles, i)
        end
        if proj.pos.x > world.bl.x + world.size.x then
            deli(projectiles, i)
        end
    end

    printh(#projectiles)

end

function _draw() 
    cls()
    for _, v in ipairs(static_bodies) do
        local s = screen_space(v.pos)
        local r = screen_space_scale(v.radius)
        circfill(s.x, s.y, r)
    end

    for _, v in ipairs(bodies) do
        local s = screen_space(v.pos)
        local r = screen_space_scale(v.radius)
        circfill(s.x, s.y, r)
    end

    for _, p in ipairs(projectiles) do
        local s = screen_space(p.pos)
        local r = screen_space_scale(p.radius)
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
