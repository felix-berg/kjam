local gravity_constant = 10

local bodymt = {}
bodymt.__index = bodymt;

function make_body(pos, vel, mass, radius)
    local sb = {
        pos = pos, 
        vel = vel,
        acc = makevec2d(0, 0),
        mass = mass,
        radius = radius 
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
    printh(self.acc)
    self.vel += self.acc * dt
    self.pos += self.vel * dt
    self.acc:set(0, 0)
end

function bodymt:attract_to(body)
    local f = attraction_force(self.pos, self.mass, body.pos, body.mass)
    local d = body.pos - self.pos
    d:set_size(f)
    self:add_force(d)
end
