
local particles = {}

local PARTICLE_SPARK = 1
local PARTICLE_SMOKE = 2

function make_particle(type, col, pos, vel, life)
    local particle = {
        type = type,
        col = col,
        pos = pos:copy(),
        vel = vel:copy(),
        drag = 0.95,
        life = life,
        age = 0,
    }

    add(particles, particle)

    return particle
end

function update_particles()
    for i = #particles, 1, -1 do
        particle = particles[i]

        particle.vel *= particle.drag
        particle.pos += particle.vel / 60

        particle.age += 1
        if particle.age > particle.life then
            deli(particles, i)
        end
    end
end

function draw_particle(particle)
    local s = screen_space(particle.pos)
    if particle.type == PARTICLE_SPARK then
        pset(s.x, s.y, particle.col)
    elseif particle.type == PARTICLE_SMOKE then
        circfill(s.x, s.y, 4 - 4 * (particle.age / particle.life), particle.col)
    end
end

function draw_particles()
    for i, particle in ipairs(particles) do
        draw_particle(particle)
    end
end
