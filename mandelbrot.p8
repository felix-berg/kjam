pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

local screen = {
    width = 128, height = 128
}

local controls = {
    left = ⬅️,
    right = ➡️,
    up = ⬆️,
    down = ⬇️,
    x = ❎,
    o = 🅾️
}

local colorMap = {
    { lim = 0.01, col = 15 },
    { lim = 0.025, col = 14 },
    { lim = 0.050, col = 13 },
    { lim = 0.075, col = 12 },
    { lim = 0.100, col = 11 },
    { lim = 0.133, col = 10 },
    { lim = 0.166, col = 9 },
    { lim = 0.2, col = 8 },
    { lim = 0.25, col = 7 },
    { lim = 0.3, col = 6 },
    { lim = 0.4, col = 4 },
    { lim = 0.53, col = 3 },
    { lim = 0.65, col = 2 },
    { lim = 0.7, col = 1 },
    { lim = 1.0, col = 0 },
}

cls(0)

printh("Hello, world!")

function generateMandelBrot(tlreal, tlimag, wreal, wimag, iterations)
    cls(0)
    for i = 1, screen.height do
        local cimag = tlimag + (wimag / screen.height) * i
        for j = 1, screen.width do
            local creal = tlreal + (wreal / screen.width) * j
            
            local zreal = 0
            local zimag = 0
            
            local k = 1
            while k <= iterations and zreal * zreal + zimag * zimag < 100 do
                local a = zreal * zreal - zimag * zimag
                zimag = 2 * zreal * zimag + cimag
                zreal = a + creal
                
                k += 1
            end
            
            for l = 1, #colorMap do
                local m = colorMap[l]
                local f = k / iterations
                if f <= m.lim then
                    pset(j, i, m.col)
                    break
                end
            end
        end
    end
end


local tlr = -1.5
local tli = -1

local wr = 2
local wi = 2
local iterations = 128

generateMandelBrot(tlr, tli, wr, wi, iterations)

function _update() 
    local step = wr * 0.1
    local regenerate = false
    if btn(controls.left) then tlr -= step; regenerate = true end
    if btn(controls.right) then tlr += step; regenerate = true end
    if btn(controls.up) then tli -= step; regenerate = true end
    if btn(controls.down) then tli += step; regenerate = true end
    if btn(controls.o) then wr = wr * 0.8; wi = wr * 0.8; regenerate = true end 
    if btn(controls.x) then wr = wr * 1.2; wi = wr * 1.2; regenerate = true end
    
    if regenerate then generateMandelBrot(tlr, tli, wr, wi, iterations) end
end 

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
