local gravity_constant = 10

local PLANET = 1
local SUN = 2
local PROJECTILE = 3

local bodymt = {}
bodymt.__index = bodymt

function make_body(pos, vel, mass, radius, type, is_static)
    local sb = {
        pos = pos,
        vel = vel,
        acc = makevec2d(0, 0),
        mass = mass,
        radius = radius,
        type = type,
        is_static = is_static
    }
    
    setmetatable(sb, bodymt)
    return sb
end

function attraction_force(p1, m1, p2, m2)
    local dist_sq = (p1 - p2):sizesq()
    local force = gravity_constant * (m1 * m2 / dist_sq)
    return force
end

function bodymt:add_force(force)
    self.acc += force / self.mass
end

function bodymt:update(dt)
    self.vel += self.acc * dt
    self.pos += self.vel * dt
    self.acc:set(0, 0)
end

local gravity_range = 100
function bodymt:attract_to(body)
    local d = body.pos - self.pos
    if d:sizesq() > gravity_range * gravity_range then return end

    local f = attraction_force(self.pos, self.mass, body.pos, body.mass)
    d:set_size(f)
    self:add_force(d)
end

function collides(b1, b2)
    return (b2 - b1):sizesq() < (b1.radius + b2.radius) * (b1.radius + b2.radius)
end