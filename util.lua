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

function gamepad_dir(playeridx)
    local v = makevec2d(0, 0)

    if btn(controls.left, playeridx)  then v.x += -1 end
    if btn(controls.right, playeridx) then v.x += 1 end
    if btn(controls.down, playeridx)  then v.y += 1 end
    if btn(controls.up, playeridx)    then v.y += -1 end

    if v.x == 0 and v.y == 0 then 
        return v 
    end

    return v:unit()
end

function lerp(t, min, max)
    return t * (max - min) + min
end

function map(val, old_min, old_max, min, max)
    local t = ((val - old_min) / (old_max - old_min))
    return lerp(t, min, max)
end

function random_btwn(min, max)
    return rnd(max - min) + min
end

function tangent_vel(b1, b2)
    local d = b2.pos - b1.pos
    local com
    if b1.is_static then
        return makevec2d(0, 0)
    elseif b2.is_static then
        com = b2.pos
    else
        com = (b1.pos * b1.mass + b2.pos * b2.mass) / (b1.mass + b2.mass)
    end
    local c = com - b1.pos
    local dir = makevec2d(-d.y, d.x)
    dir:normalize()
    local vel = sqrt(gravity_constant * b2.mass * c:size() / d:sizesq())
    return dir * vel
end