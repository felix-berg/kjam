
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
    return makevec2d(
        self.x + other.x, 
        self.y + other.y
    )
end

function vecmt.__sub(self, other)
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
    else
        return makevec2d(
            a.x * b,
            a.y * b
        )
    end
end

function vecmt:__eq(self, other)
    return self.x == other.x and self.y == other.y
end

function vecmt:__tostring()
    return self.x .. ", " .. self.y
end

function vecmt.__div(a, b)
    if type(a) == "number" then
        return makevec2d(
            b.x / a,
            b.y / a
        )
    else
        return makevec2d(
            a.x / b,
            a.y / b
        )
    end
end

-- function vecmt:__eq(a, b)
--     return a.x == b.x and a.y == b.y
-- end

function vecmt:set(x, y)
    self.x = x
    self.y = y
end

function vecmt:addv(other)
    self.x += other.x
    self.y += other.y
end

function vecmt:subv(other)
    self.x -= other.x
    self.y -= other.y
end

function vecmt:mul(scalar)
    self.x *= scalar
    self.y *= scalar
end

function vecmt:div(scalar)
    self.x /= scalar
    self.y /= scalar
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
