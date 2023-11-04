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
