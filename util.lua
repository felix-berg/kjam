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

function lerp(t, min, max)
    return t * (max - min) + min
end

function map(val, old_min, old_max, min, max)
    local t = ((val - old_min) / (old_max - old_min))
    return lerp(t, min, max)
end
