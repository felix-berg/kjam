pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- astroy
-- by felix and mathias

my_seed = 0
game_state = "title"

sounds = {
	projectile = 0,
	sun_swallow = 1,
	planet_explosion = 2,
	planet_explosion_rumble = 3,
	projectile_explosion = 4,
	out_of_bounds_beep = 5,
	round_win = 16,
	game_win_lead = 21,
	game_win_bass = 22,
}

-- random number in interval [min, max)
function random_btwn(min, max)
	return rnd(max - min) + min
end

-- compute distance
function dist(dx, dy)
	dx = dx >> 0x5
	dy = dy >> 0x5

	local dsq = dx*dx + dy*dy

	-- in case of overflow/wrap
	if (dsq < 0) return 32767.99999

	return sqrt(dsq) << 0x5
end

function out_of_bounds(x, y)
	return x < 0 or x > 128 or y < 0 or y > 128
end

-- called at start by pico-8
function _init()
	poke(0x5f36, 0x40) -- disable print scrolling
	poke(0x5f5c, 255) -- set btnp to never repeat

	my_seed = rnd(0xffff.ffff)
	init_selection_screen()
	init_starfield()
	srand(my_seed)
end

function transition_fsm(state)
	if game_state == "title" then
		if state == "level" then
			game_state = "level"

			local plr1 = menu_players[0]
			local plr2 = menu_players[1]
			add_player(plr1.id, characters[plr1.selection], 8, 2)
			add_player(plr2.id, characters[plr2.selection], 12, 1)

			random_level()
		end
	elseif game_state == "level" then
		if state == "title" then
			game_state = "title"

			players = {}
		end
	end
end

function update_fsm()
	if game_state == "title" then
		update_selection_screen()
	elseif game_state == "level" then
		update_game()
	end
end

-- called by pico-8 60 times per sec
function _update60()
	update_fsm()
	update_particles()
	update_starfield()
end

-- called once per frame by pico-8
function _draw()
	cls()
	fillp()

	draw_starfield()
	draw_particles()

	if game_state == "title" then
		draw_selection_screen()
	elseif game_state == "level" then
		draw_game()
	end
end

-->8
-- game

gameover_t = 0
winner = nil
max_wins = 5

function endgame_logic()
	gameover_t += 1
	if gameover_t > 60 then
		-- next round
		gameover_t = 0
		
		if winner != nil and winner.wins >= max_wins then
			transition_fsm("title")
			sfx(sounds.game_win_lead)
			sfx(sounds.game_win_bass)
		else
			random_level()
		end

		winner = nil

	end
	
	-- i hate it too
	if gameover_t == 30 then
		for player in all(players) do
			if player.alive then 
				player.wins += 1
				winner = player
				sfx(sounds.round_win + winner.wins - 1)
				-- printh("Winner was player with controller #" .. winner.index)
			end
		end        
	end
end

function update_game()
	-- update_player_controls()

	-- remove_dead_projectiles()
	-- update_collisions()

	-- projectile trails
	for _, body in ipairs(bodies) do
		if body.type == PROJECTILE then
			particle_projectile_trail(body.x, body.y)
		end
	end

	for player in all(players) do
		update_player(player)
	end

	local players_alive = 0
	for player in all(players) do
		players_alive = player.alive and players_alive + 1 or players_alive
	end

	if players_alive <= 1 then
		endgame_logic()
	end

	for player in all(players) do
		if (player.alive) update_out_of_bounds_time(player)
	end

	update_bodies()
end

function draw_game()
	-- draw bodies before
	for body in all(bodies) do
		if body.type == HOLE then
			draw_black_hole(body.x, body.y, body.radius, true)
		end
	end

	-- draw asteroids
	for i, asteroid in pairs(asteroids) do
		local tile = flr(asteroid.rand * 4)
		local tile_x = tile % 2
		local tile_y = flr(tile / 2)
		sspr(64 + tile_x * 4, 8 + tile_y * 4, 4, 4, asteroid.x - 1.5, asteroid.y - 1.5)
	end

	-- draw bodies
	for body in all(bodies) do
		if body.type == PLANET then
			if fget(body.sprite, 0) then -- fragment sprite flag
				pal(11, body.col1)
				pal(12, body.col2)
				local sprite_x = body.sprite % 16
				local sprite_y = body.sprite \ 16
				local tile = flr(body.rand * 4)
				local tile_x = tile % 2
				local tile_y = flr(tile / 2)
				sspr(sprite_x * 8 + tile_x * 4, sprite_y * 8 + tile_y * 4, 4, 4, body.x - 1.5, body.y - 1.5)
				pal()
			elseif fget(body.sprite, 1) then -- big sprite flag
				spr(body.sprite, body.x - 7.5, body.y - 7.5, 2, 2)
			else
				spr(body.sprite, body.x - 3.5, body.y - 3.5)
			end
		elseif body.type == PROJECTILE then
			spr(body.sprite, body.x - 3.5, body.y - 3.5)
		elseif body.type == SUN then
			draw_sun(body.x, body.y)
		elseif body.type == HOLE then
			draw_black_hole(body.x, body.y, body.radius, false)
		else
			circ(body.x, body.y, body.radius)
		end
	end

	-- draw aiming arrows
	for player in all(players) do
		if player.alive then
			draw_aiming_arrows(player)
			draw_out_of_bounds_ui(player)
		end
	end
	
	-- draw stars above winner
	if winner != nil then
		draw_winner()
	end
end

-->8
-- players

num_players = 2

player_mass = 4

shoot_delay = 0.3
shoot_strength = 50
recoil_strength = 280

player_colors = {
[0] = {8,  2},
[1] = {12, 1},
[2] = {11, 3},
[3] = {14, 2}
}

players = {}

function add_player_body(player, x, y)
	local body = body_create(x, y)
	body.mass = player_mass
	body.radius = 2.5
	body.type = PLANET
	body.sprite = player.sprite

	player.body = body
	player.alive = true

	return body
end

function add_player(playeridx, sprite, fg_color, bg_color)
	local player = {
		id = playeridx,
		body = nil,
		alive = true,
		aim_x = 0,
		aim_y = 0,
		sprite = sprite,
		wins = 0,
		out_of_bounds_time = 0,
		fg_color = fg_color,
		bg_color = bg_color,
		last_shot_t = 0
	}

	add(players, player)

	return player
end

function shoot_projectile(player)
	local now = time()
	if (now - player.last_shot_t < shoot_delay) return

	player.last_shot_t = now

	if (player.aim_x == 0 and player.aim_y == 0) return

	local body = player.body
	-- body:add_force(calculate_recoil(body, shootdir))

	local speed = dist(body.dx, body.dy)
	local dot = body.dx * player.aim_x + body.dy * player.aim_y
	local brake = (dot / speed) * 2.5 + 3.5

	body.ddx -= player.aim_x * recoil_strength * brake
	body.ddy -= player.aim_y * recoil_strength * brake

	sfx(sounds.projectile)

	-- offset projectile position by player radius in the shooting direction
	local proj_x = body.x + player.aim_x * body.radius * 2
	local proj_y = body.y + player.aim_y * body.radius * 2
	local vx = player.aim_x * (shoot_strength + max(dot) * 0.5)
	local vy = player.aim_y * (shoot_strength + max(dot) * 0.5)
	add_projectile(proj_x, proj_y, vx, vy)
end

function update_player(player)
	if not player.alive then return end

	local id = player.id

	-- aim
	player.aim_x = 0
	player.aim_y = 0
	if (btn(0, id)) player.aim_x -= 1
	if (btn(1, id)) player.aim_x += 1

	if (btn(2, id)) player.aim_y -= 1
	if (btn(3, id)) player.aim_y += 1

	if player.aim_x != 0 and player.aim_y != 0 then
		player.aim_x *= 0.7
		player.aim_y *= 0.7
	end

	if player.aim_x != 0 or player.aim_y != 0 then
		if btnp(4, id) then
			shoot_projectile(player)
		end
	end

	if not player.body.alive then
		player.alive = false
	end
end

local out_of_bounds_death_time = 300
function update_out_of_bounds_time(player)
	if out_of_bounds(player.body.x, player.body.y) then
		player.out_of_bounds_time += 1
	else
		player.out_of_bounds_time = 0
	end
	if player.out_of_bounds_time > out_of_bounds_death_time then
		del(bodies, player.body)
		player.alive = false
	end
end

-->8
-- bodies

bodies = {}

gravity_constant = 1

PLANET = 1
PROJECTILE = 2
SUN = 3
HOLE = 4

-- local DYNAMIC = false
-- local STATIC = true

function body_create(x, y)
	x = x or 64 -- default pos
	y = y or 64
	local b = {
		type = PLANET,
		alive = true,
		static = false,
		mass = 1,
		radius = 1,
		x = x, -- position
		y = y,
		dx = 0, -- velocity
		dy = 0,
		ddx = 0, -- acceleration
		ddy = 0,
		sprite = 1,
		col1 = 11, -- primary color (used by fragments)
		col2 = 12, -- secondary color
		rand = rnd()
	}

	add(bodies, b)

	return b
end

function body_destroy(body)
	body.alive = false
	del(bodies, body)
end

-- add exploding fragments of this body exploding into the "bodies" table
function body_fragment(body, fragment_count)
	if fget(body.sprite, 0) then return end -- body is already a fragment

	-- sample body sprite to get primary and secondary colors used by fragments
	local col1 = 0
	local col2 = 0
	local sprite_x = body.sprite % 16
	local sprite_y = body.sprite \ 16
	if fget(body.sprite, 1) then
		for x = 4, 11 do
			local col = sget(sprite_x * 8 + x, sprite_y * 8 + 7)
			if col != 0 then
				if col1 == 0 then
					col1 = col
				elseif col != col1 then
					col2 = col
					break
				end
			end
		end
	else
		for x = 0, 7 do
			local col = sget(sprite_x * 8 + x, sprite_y * 8 + 3)
			if col != 0 then
				if col1 == 0 then
					col1 = col
				elseif col != col1 then
					col2 = col
					break
				end
			end
		end
	end

	-- each fragment has a nth size and radius
	local mass = body.mass / (fragment_count * 10)
	local radius = 0.4 * body.radius / fragment_count 

	local min_dist = radius + body.radius

	local angle_offset = rnd()

	for i = 1, fragment_count do
		local angle = i / fragment_count + random_btwn(-0.1, 0.1)

		local strength = random_btwn(12, 20)

		local c = cos(angle)
		local s = sin(angle)

		local frag_body = body_create(body.x + c * min_dist, body.y + s * min_dist)
		frag_body.dx = c * strength
		frag_body.dy = s * strength
		frag_body.mass = mass
		frag_body.radius = radius
		frag_body.sprite = 8
		frag_body.col1 = col1
		frag_body.col2 = col2
	end
end

function add_planet(x, y, mass, radius)
	local body = body_create(x, y)
	body.type = PLANET
	body.static = false
	body.mass = mass
	body.radius = radius
	body.sprite = 1

	return body
end

function add_sun(x, y, mass, radius)
	local body = body_create(x, y)
	body.type = SUN
	body.static = true
	body.mass = mass
	body.radius = radius
	body.sprite = 0

	return body
end

function add_projectile(x, y, dx, dy)
	local p = body_create(x, y)
	p.type = PROJECTILE
	p.static = false
	p.mass = 0.5
	p.radius = 1.6
	p.dx = dx
	p.dy = dy
	p.sprite = 12

	return p
end

-- function remove_dead_projectiles()
--    for _, body in ipairs(bodies) do
-- 		if body.type == PROJECTILE and out_of_bounds(proj.pos) then 
-- 			del(bodies, body)
-- 		end
--    end
-- end

asteroid_radius = 1.25

asteroids = {}

function asteroid_get(cell_x, cell_y)
	if cell_x < 0 or cell_x > 15 or
		cell_y < 0 or cell_y > 15 then
		return nil
	end
	local index = cell_y * 16 + cell_x
	return asteroids[index]
end

function asteroid_add(cell_x, cell_y)
	local a = {
		x = cell_x * 8 + 4 + (rnd(2) - 1) * 2.5,
		y = cell_y * 8 + 4 + (rnd(2) - 1) * 2.5,
		rand = rnd()
	}
	local index = cell_y * 16 + cell_x
	asteroids[index] = a

	return a
end

function asteroid_remove(cell_x, cell_y)
	local index = cell_y * 16 + cell_x
	asteroids[index] = nil
end

local dt = 1 / 60
function update_bodies()
	-- dynamic bodies attract to static bodies and each other
	local collisions = {}
	
	for i = 1, #bodies do
		local b1 = bodies[i]

		-- body collisions
		for j = i + 1, #bodies do
			local b2 = bodies[j]

			local dx = b2.x - b1.x
			local dy = b2.y - b1.y
			dx = dx >> 0x5
			dy = dy >> 0x5
			local dsq = dx*dx + dy*dy
			local d = sqrt(dsq)

			-- if d > gravity_range then return end

			-- check collision
			if (d << 0x5) <= b1.radius + b2.radius then
				if b2.type > b1.type then
					add(collisions, { first = b1, second = b2 })
				else
					add(collisions, { first = b2, second = b1 })
				end
			end

			-- apply gravity forces
			local a1 = b1.static and 0 or gravity_constant * b2.mass / dsq
			local a2 = b2.static and 0 or gravity_constant * b1.mass / dsq
			b1.ddx += (dx / d) * a1
			b1.ddy += (dy / d) * a1
			b2.ddx -= (dx / d) * a2
			b2.ddy -= (dy / d) * a2
		end

		-- asteroid collisions
		local x1 = (b1.x - b1.radius) \ 8
		local y1 = (b1.y - b1.radius) \ 8
		local x2 = (b1.x + b1.radius) \ 8
		local y2 = (b1.y + b1.radius) \ 8
		for y = y1, y2 do
			for x = x1, x2 do
				local a = asteroid_get(x, y)
				if a then
					local dx = a.x - b1.x
					local dy = a.y - b1.y
					local dsq = dx*dx + dy*dy
					-- check collision
					if dsq <= (b1.radius + asteroid_radius) * (b1.radius + asteroid_radius) then
						add(collisions, { first = b1, second = nil })
						asteroid_remove(x, y)
					end
				end
			end
		end
	end

	for pair in all(collisions) do
		local b1 = pair.first
		local b2 = pair.second

		if b1.type == SUN or b1.type == HOLE then
			-- do nothing
		elseif b2 == nil then
			-- fragment planets
			if b1.type == PLANET then
				body_fragment(b1, 3)
			end

			-- explosion particle effect
			particle_explosion(b1.x, b1.y, b1.radius)

			-- play explosion sound
			if b1.radius > 2 then
				sfx(sounds.planet_explosion)
			else
				sfx(sounds.projectile_explosion)
			end

			body_destroy(b1)
		elseif b2.type == HOLE then
			body_destroy(b1)
		elseif b2.type == SUN then
			-- particle effects
			local dx = b1.x - b2.x
			local dy = b1.y - b2.y
			particle_sun_emit(b2.x, b2.y, dx, dy)

			-- play sound
			sfx(sounds.sun_swallow)

			body_destroy(b1)
		elseif b2 != nil then
			-- fragment planets
			if b1.type == PLANET then
				body_fragment(b1, 3)
			end
			if b2.type == PLANET then
				body_fragment(b2, 3)
			end

			-- explosion particle effect
			particle_explosion(b1.x, b1.y, b1.radius)
			particle_explosion(b2.x, b2.y, b2.radius)

			-- play explosion sound
			if b1.radius > 2 or b2.radius > 2 then
				sfx(sounds.planet_explosion)
			else
				sfx(sounds.projectile_explosion)
			end

			body_destroy(b1)
			body_destroy(b2)
		end
	end

	for body in all(bodies) do
		if not body.static then
			body.dx += body.ddx * dt
			body.dy += body.ddy * dt
			body.x += body.dx * dt
			body.y += body.dy * dt
		end
		body.ddx = 0
		body.ddy = 0
	end
end

-->8
-- particles

particles = {}

PARTICLE_SPARK = 1
PARTICLE_SMOKE = 2
PARTICLE_BUBBLE = 3

function make_particle(type, col, x, y)
	local particle = {
		type = type,
		col = col,
		x = x,
		y = y,
		dx = 0,
		dy = 0,
		drag = 0.95,
		size = 10,
		life = 60,
		age = 0,
	}
	
	add(particles, particle)
	
	return particle
end

function update_particles()
	for i = #particles, 1, -1 do
		particle = particles[i]
		
		particle.dx *= particle.drag
		particle.dy *= particle.drag
		particle.x += particle.dx
		particle.y += particle.dy
		
		particle.age += 1
		if particle.age >= particle.life then
			deli(particles, i)
		end
	end
end

function particle_explosion(x, y, radius)
	local colors = {5, 5, 8, 8, 9, 9, 10, 10}
	for i = 1, 8 do
		local off_range = 2 * radius
		local vel_range = 0.08 * radius
		local life = radius * rnd(70) + 15

		local particle = make_particle(
			PARTICLE_SMOKE,
			colors[i],
			x + random_btwn(-off_range, off_range),
			y + random_btwn(-off_range, off_range)
		)
		particle.dx = random_btwn(-vel_range, vel_range)
		particle.dy = random_btwn(-vel_range, vel_range)
		particle.life = life
	end
end

function particle_sun_emit(x, y, dx, dy)
	for i = 1, 20 do
		-- local speed = random_btwn(0.06, 0.2)
		local speed_scale = rnd(0.25) + 0.1
		local col = rnd(2) + 8
		local particle = make_particle(PARTICLE_SPARK, col, x, y)
		particle.dx = dx * speed_scale + random_btwn(-0.4, 0.4)
		particle.dy = dy * speed_scale + random_btwn(-0.4, 0.4)
		particle.life = rnd(60) + 30
	end
end

function particle_projectile_trail(x, y, dx, dy)
	-- local dir = body.vel * -0.2
	-- dir:normalize()
	local col = rnd(2) + 9
	local particle = make_particle(PARTICLE_SPARK, col, x, y)
	particle.dx = random_btwn(-0.2, 0.2)
	particle.dy = random_btwn(-0.2, 0.2)
	particle.life = rnd(6) + 10
end

function particle_bubble(x, y, radius, size, col)
	local particle = make_particle(PARTICLE_BUBBLE, col, x, y)
	particle.size = size
	particle.life = radius
end

function draw_particles()
	for particle in all(particles) do
		if particle.type == PARTICLE_SPARK then
			pset(particle.x, particle.y, particle.col)
		elseif particle.type == PARTICLE_SMOKE then
			circfill(particle.x, particle.y, 4 - 4 * (particle.age / particle.life), particle.col)
		elseif particle.type == PARTICLE_BUBBLE then
			local t = particle.age / particle.life
			t = 1 - (1 - t)^2
			circ(particle.x, particle.y, t * particle.size + 6, particle.col)
		end
	end
end

-->8
-- levels

num_levels = 13

function body_data_com(body_dat, use_static_mass)
	local static_mass = 0
	local total_mass = 0
	local comx = 0
	local comy = 0
	local static = false

	-- compute the center of mass of bodies
	for bdat in all(body_dat) do
		if not static and bdat.static then
			static = true
			static_mass = 0
			comx = 0
			comy = 0
		end

		if #bdat == 0 then
			if (bdat.static) or (#bdat == 0 and not static) then
				local m = bdat.mass or (bdat.plr and player_mass or 1)
				static_mass += m
				total_mass += m
				comx += bdat.pos[1] * m
				comy += bdat.pos[2] * m
			end
		else
			local m, cx, cy, stc = body_data_com(bdat)
			if not static and stc then
				static = true
				static_mass = 0
				comx = 0
				comy = 0
			end
			static_mass += m
			total_mass += m
			comx += cx * m
			comy += cy * m
		end
	end
	comx /= static_mass
	comy /= static_mass

	if (use_static_mass) total_mass = static_mass
	return total_mass, comx, comy, static
end

-- create bodies from level body data, and set the initial orbital velocities
function setup_bodies(body_dat, rel_x, rel_y)
	local mass, comx, comy, static = body_data_com(body_dat, true)

	-- init bodies
	for bdat in all(body_dat) do
		if #bdat == 0 then
			local b
			if bdat.plr then
				b = add_player_body(players[bdat.plr], bdat.pos[1], bdat.pos[2])
				b.mass = bdat.mass or player_mass
			else
				b = body_create(bdat.pos[1], bdat.pos[2])
				b.type = bdat.type or PLANET
				b.static = bdat.static or false
				b.mass = bdat.mass or 1
				b.radius = bdat.radius or 1
				b.sprite = bdat.sprite or 1
			end
			b.dx = rel_x
			b.dy = rel_y
			if not bdat.static and mass > b.mass then
				local m = static and mass or mass - b.mass

				local dx = comx - b.x
				local dy = comy - b.y
				dx = dx >> 0x4
				dy = dy >> 0x4
				local dsq = dx*dx + dy*dy
				local d = sqrt(dsq)

				-- approximate distance to center of mass of all other bodies (excluding this one)
				local dc = d * mass / m

				-- eccentricity
				local ecc = bdat.ecc or 0
				-- velocity
				local vel = 8 * sqrt(gravity_constant * m * (d - d * ecc)) / dc -- thankyou kepler

				b.dx += -dy / d * vel
				b.dy +=  dx / d * vel
			end
		else
			local asm_mass, asm_comx, asm_comy, asm_static = body_data_com(bdat)
			local asm_vx = rel_x
			local asm_vy = rel_y
			if not asm_static and mass > asm_mass then
				local m = static and mass or mass - asm_mass

				local dx = comx - asm_comx
				local dy = comy - asm_comy
				dx = dx >> 0x4
				dy = dy >> 0x4
				local dsq = dx*dx + dy*dy
				local d = sqrt(dsq)

				-- approximate distance to center of mass of all other bodies (excluding this one)
				local dc = d * mass / m

				-- eccentricity
				local ecc = bdat.ecc or 0
				-- velocity
				local vel = 8 * sqrt(gravity_constant * m * (d - d * ecc)) / dc -- thankyou kepler

				asm_vx += -dy / d * vel
				asm_vy +=  dx / d * vel

			end
			setup_bodies(bdat, asm_vx, asm_vy)
		end
	end
end

function setup_asteroid_belt(belt)
	local cell_x = (belt % 8) * 16
	local cell_y = (belt \ 8) * 16

	for y = 0, 15 do
		for x = 0, 15 do
			if mget(cell_x + x, cell_y + y) == 24 then
				asteroid_add(x, y)
			end
		end
	end
end

function random_level()
	init_level(flr(rnd(num_levels)) + 1)
end

function init_level(lvl)
	local ldat = level_dat[lvl]
	if (not ldat) return

	cls()
	reset()

	bodies = {}
	asteroids = {}

	for player in all(players) do
		player.alive = true
		player.last_shot_t = time() + 1
	end

	setup_bodies(ldat.bodies, 0, 0)

	if ldat.belt then
		setup_asteroid_belt(ldat.belt)
	end

	-- elseif level == 9 then
	-- 	-- two suns, two planets, two players
		
	-- 	local sun1 = add_sun(makevec2d(-4, -4), 16, 0.8)
	-- 	local sun2 = add_sun(makevec2d( 4,  4), 16, 0.8)

	-- 	local purple = add_planet(makevec2d(-2, -4), 3, 0.2)
	-- 	local green = add_planet(makevec2d( 2, 4), 3, 0.2)
	-- 	purple.vel = tangent_vel(purple, sun1)
	-- 	green.vel = tangent_vel(green, sun2)
	-- 	purple.sprite = 2
	-- 	green.sprite = 34

	-- 	local b1 = add_player_body(players[1], makevec2d(-4, 4), makevec2d(0, 0), 0)
	-- 	local b2 = add_player_body(players[2], makevec2d(4, -4), makevec2d(0, 0), 0)
	-- elseif level == 10 then
	-- 	-- figure 8

	-- 	local factor = 2.3
	-- 	local b1 = add_player_body(players[1], makevec2d(0.97, -0.243) * factor, makevec2d(0, 0), 0)
	-- 	local b2 = add_player_body(players[2], makevec2d(-0.97, 0.243) * factor, makevec2d(0, 0), 0)
	-- 	local green = add_planet(makevec2d(0, 0), 6, 0.2)

	-- 	b1.vel = makevec2d(0.932, 0.864) * factor * 0.5
	-- 	b2.vel = makevec2d(0.932, 0.864) * factor * 0.5
	-- 	green.vel = makevec2d(-0.932, -0.864) * factor
	-- 	green.sprite = 34
	-- end
end

level_dat = {

-- 1: two players in regular orbit
{
	bodies = {

	{
		plr = 1,
		pos = {32, 32}
	},
	{
		plr = 2,
		pos = {96, 96}
	},

	}
},

-- 2: two players in close orbit with few asteroids
{
	bodies = {

	{
		plr = 1,
		pos = {80, 48}
	},
	{
		plr = 2,
		pos = {48, 80}
	},

	},

	belt = 2
},

-- 3: two players with outer asteroid belt
{
	bodies = {

	{
		plr = 1,
		pos = {32, 32}
	},
	{
		plr = 2,
		pos = {96, 96}
	},

	},

	belt = 1
},

-- 4: two players in close elliptic orbit
{
	bodies = {

	{
		plr = 1,
		pos = {60, 64},
		ecc = -0.65
	},
	{
		plr = 2,
		pos = {68, 64},
		ecc = -0.65
	},

	},
},

-- 5: sun and two planets
{
	bodies = {

	{
		plr = 1,
		pos = {32, 32}
	},
	{
		plr = 2,
		pos = {96, 96}
	},
	{
		type = SUN,
		static = true,
		mass = 16,
		radius = 6,
		pos = {64, 64}
	},

	}
},

-- 6: sun and two planets
{
	bodies = {

	{
		plr = 1,
		pos = {28, 28}
	},
	{
		plr = 2,
		pos = {100, 100}
	},
	{
		type = SUN,
		static = true,
		mass = 16,
		radius = 6,
		pos = {64, 64}
	},

	},

	belt = 3
},

-- 7: sun, mercury, and two planets
{
	bodies = {

	{
		plr = 1,
		pos = {24, 104}
	},
	{
		plr = 2,
		pos = {104, 24}
	},
	{
		{
			type = SUN,
			static = true,
			mass = 16,
			radius = 6,
			pos = {64, 64}
		},
		{
			sprite = 3,
			mass = 2,
			radius = 2,
			pos = {64, 50}
		},
	},

	}
},

-- 8: two suns
{
	bodies = {

	{
		{
			plr = 1,
			pos = {32, 40}
		},
		{
			type = SUN,
			static = true,
			mass = 16,
			radius = 6,
			pos = {32, 64}
		},
	},
	{
		{
			plr = 2,
			pos = {96, 88}
		},
		{
			type = SUN,
			static = true,
			mass = 16,
			radius = 6,
			pos = {96, 64}
		},
	},

	}
},

-- 9: sun and moons
{
	bodies = {

	{
		{
			plr = 1,
			pos = {104, 24}
		},
		{
			mass = 0.5,
			radius = 1.5,
			pos = {95, 24},
			sprite = 6
		},
	},
	{
		{
			plr = 2,
			pos = {24, 104}
		},
		{
			mass = 0.5,
			radius = 1.5,
			pos = {33, 104},
			sprite = 6
		},
	},
	{
		type = SUN,
		static = true,
		mass = 16,
		radius = 6,
		pos = {64, 64}
	},

	}
},

-- 10: sun and saturn
{
	bodies = {

	{
		mass = 8,
		radius = 3.5,
		pos = {116, 15},
		sprite = 32
	},
	{
		plr = 1,
		pos = {80, 48}
	},
	{
		plr = 2,
		pos = {48, 80}
	},
	{
		type = SUN,
		static = true,
		mass = 16,
		radius = 6,
		pos = {64, 64}
	},

	}
},

-- 11: venus and comet
{
	bodies = {

	{
		plr = 1,
		pos = {20, 20}
	},
	{
		plr = 2,
		pos = {104, 104}
	},
	{
		{
			mass = 2,
			radius = 3.5,
			pos = {64, 76},
			sprite = 4
		},
		{
			type = SUN,
			static = true,
			mass = 16,
			radius = 6,
			pos = {64, 64}
		},
	},
	{
		mass = 0.5,
		radius = 1,
		pos = {64, 144},
		ecc = 0.9,
		sprite = 16
	},

	}
},

-- 12: close and far orbit + satellite
{
	bodies = {

	{
		plr = 1,
		pos = {64, 80}
	},
	{
		plr = 2,
		pos = {64, 120}
	},
	{
		type = SUN,
		static = true,
		mass = 16,
		radius = 6,
		pos = {64, 64}
	},	
	{
		mass = 0.2,
		radius = 2,
		pos = {64, 8},
		sprite = 17
	},

	}
},

-- 13: black hole and two planets
{
	bodies = {

	{
		plr = 1,
		pos = {20, 20}
	},
	{
		plr = 2,
		pos = {108, 108}
	},
	{
		type = HOLE,
		static = true,
		mass = 32,
		radius = 6,
		pos = {64, 64}
	},

	}
},

}

-->8
-- pause menu

characters = {1, 2, 3, 4}

menu_players = {}
ui_character_frames = {}

menu_countdown = 0
menu_last_countdown_time = 0

function make_menu_player(id)
	local mp = {
		id = id,
		selected = false,
		selection = id % #characters + 1,
		x = 64,
		y = 96,
	}

	menu_players[id] = mp

	return mp
end

function init_selection_screen()
	for i = 1, #characters do
		local frame = {
			x = 24 * (i - 3) + 64,
			y = 64,
			selected = false,
		}

		ui_character_frames[i] = frame
	end
end

function begin_countdown()
	menu_countdown = 3
	menu_last_countdown_time = time()
	particle_bubble(64, 96, 10, 2, 7)
end

function advance_countdown()
	menu_countdown -= 1
	menu_last_countdown_time = time()
	particle_bubble(64, 96, 10, 2, 7)

	if (menu_countdown == 0) transition_fsm("level")
end

function update_selection_screen()
	if menu_countdown > 0 then
		if time() >= menu_last_countdown_time + 1 then
			advance_countdown()
		end

		for _, plr in pairs(menu_players) do
			if plr.selected then
				if btnp(4, plr.id) then
					advance_countdown()
				elseif btnp(5, plr.id) then
					menu_countdown = 0
				end
			end
		end
	else
		for _, plr in pairs(menu_players) do
			if plr.selected and btnp(4, plr.id) then
				begin_countdown()
			end
		end
	end

	for i = 1, #characters do
		local chr = characters[i]
		local frame = ui_character_frames[i]

		if not frame.selected then
			frame.x = 24 * (i - 3) + 64 + 1.75 * cos(0.0643 * time() + i * 0.734)
			frame.y = 64 + 1.75 * sin(0.0734 * time() + i * 0.462)
		end
	end

	for _, plr in pairs(menu_players) do
		if not plr.selected and btnp(4, plr.id) then
			plr.selected = true
			ui_character_frames[plr.selection].selected = true
			particle_bubble(plr.x, plr.y, 10, 8, player_colors[plr.id][1])
		elseif plr.selected and btnp(5, plr.id) then
			plr.selected = false
			ui_character_frames[plr.selection].selected = false
		end

		if not plr.selected then
			if btnp(0, plr.id) then
				plr.selection -= 1
				if (plr.selection < 1) plr.selection = #ui_character_frames
			elseif btnp(1, plr.id) then
				plr.selection += 1
				if (plr.selection > #ui_character_frames) plr.selection = 1
			end
		end

		local frame = ui_character_frames[plr.selection]

		plr.x += (frame.x + 7.5 - plr.x) * 0.25
		plr.y += (frame.y + 7.5 - plr.y) * 0.25
	end

	if btn() & 0x3f > 0 then
		if not menu_players[0] then
			make_menu_player(0)
		end
	end

	if btn() & 0x3f00 > 0 then
		if not menu_players[1] then
			make_menu_player(1)
		end
	end
end

function draw_selection_rect(x0, y0, x1, y1)
	sspr(64, 24, 4, 4, x0, y0, 4, 4, false, false)
	sspr(64, 24, 4, 4, x1 - 3, y0, 4, 4, true, false)
	sspr(68, 28, 4, 4, x1 - 3, y1 - 3, 4, 4, true, true)
	sspr(68, 28, 4, 4, x0, y1 - 3, 4, 4, false, true)

	sspr(68, 24, 4, 4, x0 + 4, y0, x1 - x0 - 7, 4, false, false)
	sspr(68, 24, 4, 4, x0 + 4, y1 - 1, x1 - x0 - 7, 4, false, false)
	
	sspr(64, 28, 4, 4, x0, y0 + 4, 4, y1 - y0 - 7, false, false)
	sspr(64, 28, 4, 4, x1 - 3, y0 + 4, 4, y1 - y0 - 7, true, false)
end

function draw_selection_screen()
	color(7)

	if menu_countdown > 0 then
		cursor(63, 94)
		print(menu_countdown)
	end

	for i = 1, #characters do
		local chr = characters[i]
		local ui_frame = ui_character_frames[i]

		-- rect(ui_frame.x, ui_frame.y, ui_frame.x + 15, ui_frame.y + 15)

		-- spr(56, ui_frame.x, ui_frame.y, 1, 1, false, false)
		-- spr(56, ui_frame.x + 8, ui_frame.y, 1, 1, true, false)
		-- spr(56, ui_frame.x, ui_frame.y + 8, 1, 1, false, true)
		-- spr(56, ui_frame.x + 8, ui_frame.y + 8, 1, 1, true, true)

		-- draw_selection_rect(ui_frame.x, ui_frame.y, ui_frame.x + 15, ui_frame.y + 15)

		spr(chr, ui_frame.x + 4, ui_frame.y + 4)
	end

	for _, plr in pairs(menu_players) do
		local frame = ui_character_frames[plr.selection]

		color(player_colors[plr.id][1])
		pal(8, player_colors[plr.id][1])
		pal(2, player_colors[plr.id][2])

		local yoff = -18
		cursor(plr.x - 3, plr.y + yoff - 6)
		if plr.id != 0 then
			yoff = 12
			cursor(plr.x - 3, plr.y + yoff + 9)
		end
		spr(60, plr.x - 3, plr.y + yoff, 1, 1, false, plr.id != 0)
		print("p" .. plr.id + 1)

		if plr.selected then
			circ(plr.x, plr.y + 1, 7, 2)
			circ(plr.x, plr.y, 7, 8)
		else
			for s = 0, 0.9, 0.125 do
				local off = time() * 0.3 + plr.id * 0.1
				local x0 = plr.x + 7 * cos(s + off)
				local y0 = plr.y + 7 * sin(s + off)
				local x1 = plr.x + 7 * cos(s + 0.025 + off)
				local y1 = plr.y + 7 * sin(s + 0.025 + off)

				line(x0, y0, x1, y1)
			end
		end

		-- circ(plr.x, plr.y + 1, 7, 2)
		-- circ(plr.x, plr.y, 7, 8)

		-- rectfill(plr.x, plr.y, plr.x + 1, plr.y + 1, 8)

		pal()
	end
end

-->8
-- draw

function draw_sun(x, y)
	for i = -7, 7 do
		for j = -7, 7 do
			local dist = sqrt(i * i + j * j)
			local angle = atan2(j, i)
			if dist < 5 then
				pset(x + i, y + j, 10)
			elseif dist < 6 then
				pset(x + i, y + j, 9)
			elseif dist < 8 + 1.5 * sin(4.5 * angle + 0.2 * time()) then
				pset(x + i, y + j, 8)
			end
		end
	end
end

function draw_black_hole(x, y, radius, draw_halo)
	if draw_halo then
		circfill(x, y, sin(time()) * 2 + radius + 5, 8)
		circfill(x, y, sin(time()) * 1 + radius + 3.5, 9)
	end

	circfill(x, y, radius + 2, 0)
	circ(x, y, radius + 2, 7)
end

function draw_aiming_arrows(player)
	local b = player.body

	local sx = 80
	local sy = 24

	if player.aim_x != 0 and player.aim_y != 0 then
		sy += 4
	elseif player.aim_y != 0 then
		sx += 4
	elseif player.aim_x == 0 then
		return
	end

	pal(8, player.fg_color)
	pal(2, player.bg_color)

	local arrow_x = b.x + flr(5 * player.aim_x) - 1.5
	local arrow_y = b.y + flr(5 * player.aim_y) - 1.5

	sspr(sx, sy, 4, 4,
		 arrow_x, arrow_y, 4, 4,
		 player.aim_x < 0, player.aim_y < 0)

	pal()
end

local horizontal_ob_arrow_x = 88
local horizontal_ob_arrow_y = 24
local vertical_ob_arrow_x = 96
local vertical_ob_arrow_y = 24
local diagonal_ob_arrow_x = 104
local diagonal_ob_arrow_y = 24
local ob_blink_freq = 30

function draw_out_of_bounds_ui(player)
	if not out_of_bounds(player.body.x, player.body.y) then return end

	local px = player.body.x
	local py = player.body.y
	local spritex = 0 
	local spritey = 0 

	local sprite_size = 8
	local wl_sprite_size = sprite_size

	if px > 0 and px < 128 then -- vertical
		spritex = vertical_ob_arrow_x
		spritey = vertical_ob_arrow_y
	elseif py > 0 and py < 128 then --horizontal
		spritex = horizontal_ob_arrow_x
		spritey = horizontal_ob_arrow_y
	else -- diagonal
		spritex = diagonal_ob_arrow_x
		spritey = diagonal_ob_arrow_y
	end

	local w = wl_sprite_size / 2
	if     px < 0 + w then px = w
	elseif px > 128 - w then px = 128 - w end
	if     py < 0 + w then py = w
	elseif py > 128 - w then py = 128 - w end

	local dist = max(abs(px - player.body.x), abs(py - player.body.y))
	local max_dist = 128
	local t = min(dist, max_dist) / max_dist
	local sz = ceil((1 - t) * 4 + t * 2) * 2 - 1

	if player.out_of_bounds_time >= 30 and flr(player.out_of_bounds_time / ob_blink_freq) % 2 == 0 then 
		pal(player.fg_color, 7)
		pal(player.bg_color, 6)
	else 
		pal(player.fg_color)
		pal(player.bg_color)
	end

	if player.out_of_bounds_time >= 30 and player.out_of_bounds_time % (ob_blink_freq * 2) == 0 then
		sfx(sounds.out_of_bounds_beep) 
	end

	sspr(spritex, spritey, 7, 7, px - sz / 2, py - sz / 2, sz, sz, px < 64, py < 64)
	pal()
end

function draw_winner()
	assert(winner != nil)

	local star_width = 6

	local lx = winner.body.x - (winner.wins / 2) * star_width - 0.5
	local y = winner.body.y - 7.5
	lx += 1
	for i = 1, winner.wins do
		spr(13, lx, y)
		lx += star_width
	end
end

star_particles = {}
function init_starfield()
	srand(73)
	local colors = {1, 6}
	for i = 1, 100 do
		local x = flr(rnd(128))
		local y = flr(rnd(128))
		local r = flr(rnd(2)) + 1
		local r = i <= 50 and 1 or 2
		local particle = {
			x = x,
			y = y,
			prev_x = x,
			prev_y = y - r * 0.01,
			col = colors[r]
		}
	
		add(star_particles, particle)
	end
end

function update_starfield()
	for i = 1, #star_particles do
		local particle = star_particles[i]
		local dx = particle.x - particle.prev_x
		local dy = particle.y - particle.prev_y
		particle.prev_x = particle.x
		particle.prev_y = particle.y
		particle.x += dx
		particle.y += dy
		if particle.y > 128 then
			particle.y -= 128
			particle.prev_y -= 128
		end
	end
end

function draw_starfield()
	for particle in all(star_particles) do
		line(particle.prev_x, particle.prev_y, particle.x, particle.y, particle.col)
	end
end

__gfx__
000000000000000000000000000000000000000000000000000000000000000000bc00cc00990ff900006330000000000000000000a000000000000000000000
0000000000c7cc0000222800006666000099990000dddd000000000000b22d00dcbd0bbdffffd99d560000500000000000000000aaaaa0000000000000000000
007007000bcccbc0088888800d6d6d60099944900ddd12d0000660000bd2d3b00dd00dc0dffddff0d500056000000000000000000aaa00000000000000000000
000770000bbcbbb0022882200dd666d0094499900212ddd0006765000b333bb000000dd00dd0ddd0dd6000d0000000000007e0000a0a00000000000000000000
000770000bccbbc0088822800dd6d660044994400dddd1200065670003bbb330c0000000f900fff00000000000000000000e2000000000000000000000000000
007007000ccccbc0028888800dddd66004444440022dddd0000660000b333330cb00dbc0f9f0d99f0d0000500000000000000000000000000000000000000000
0000000000c77c000022880000dd6600004444000022220000000000003d2300dbb00dcddffd0dff05500dd60000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000ddd00d00ddd00d0056606500000000000000000000000000000000000000000
000000000000800000c77c0000000000000000000000000000000000000000000044004400000000000000000000000000000000000000000000000000000000
000000006000d0600cdc7cd0000000000000000000000000000000000000000024f204f200000000000000000000000000000000000000000000000000000000
0007700030666030cddccddc00000000000000000000000000000000000000000220042000000000000000000000000000000000000000000000000000000000
00c7c70035d66530cdddccdd00000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000
0c1ccc0030ddd03011dddc2200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c1011000d00500d01122122100000000000000000000000000000000000000004f004ff000000000000000000000000000000000000000000000000000000000
10c1000000dd600001211110000000000000000000000000000000000000000024f02f2400000000000000000000000000000000000000000000000000000000
0c1000000d5556000016610000000000000000000000000000000000000000000220024000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000ff990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000f99fff9900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000fff999ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0dd999fffff99dd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d11ff999999ff11d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1ddddf999ffdddd10000000000000000000000000000000000000000000000000444444400000000028000002800000022222220000002000000000000000000
01111dddddd111100000000000000000000000000000000000000000000000004422222200000000002820022880000088888880000028000006600000000000
0000f111111f00000000000000000000000000000000000000000000000000004220000000000000002882282888000008888800000288000060060000000000
000099ffff9900000000000000000000000000000000000000000000000000004200000000000000028008802888800000888000002888000606006000000000
00000099990000000000000000000000000000000000000000000000000000004200022200000000000000002888000000080000028888000600606000000000
00000000000000000000000000000000000000000000000000000000000000004200224400000000000200002880000000000000288888000060060000000000
00000000000000000000000000000000000000000000000000000000000000004200444000000000002800002800000000000000000000000006600000000000
00000000000000000000000000000000000000000000000000000000000000004200420000000000028800000000000000000000000000000000000000000000
0009999000999990009999900999990000000a9aa900000000000006cccccc10000000000000000000000000000000000000000000006cccccc1000000000000
0099999009999990099999900999999000099a555550000000001577ccccbcccc30000000000000000000000000000000000000001577ccccbcccc3000000000
00990990099900000009900000000990005555bbbb500000005cc67cccccbbcbbbb3000000000000000000000000000000000001cc67cccccbbcbbbb30000000
0444044004444400004440000004440000bbbbbbbcc500000095cc6cccccccbbbbbb30000000000000000000000000000000003cccc6cccccccbbbbbb3000000
0440044000044400004400000004400003bbbbbcccc50000009555cccccccccbbbbb3100000000000000000000000000000003bbbcccccccccccbbbbb3100000
444004404444440004440000000044000bbbbbbccccc5000000995cccccccbbbccbb331000000000000000000000000000003bbbbbbcccccccbbbccbb3310000
440004404444400004400000000044000bbbbbbcccccc500000095cccccccbbcccbb11330000000000000000000000000003bbbbbbbcccccccbbcccbb1133000
000000000000000000000000000000003bbbbbbcccccc500000095cccccccccbbcccc133300000000000000000000000003bbbbbbbccccccccccbbcccc133300
00999900009909900244420000000000bbbbbbccccccc50000000955cccccbbbbbccb31330000000000000000000000000bbbbbbbcccccccccbbbbbccb313300
0999999000990990044f442000000000bccccbcccccccc5000000995cccccbbbbbbbbb3315000000000000000000000003bbbbbcccccccccccbbbbbbbbb33130
099099900099990004f2242000000000bcccccccccccccc5000000a5ccccbbbbbbbbb3355000000000000000000000000bbbbbbccccccccccbbbbbbbbb333110
444044400044400044f2442000000000bbbccccccccccccc500000aa5cccbbbbbb55b5500000000000000000999000000bbbbbbccccccccccbbbbbbbbbb33330
44404400004400002444442000000000cbbbcccbbccccccc5000000095ccbbbbb50050000000000000000099999900003bbbbbbccccccccccbbbbbbbbb333333
44444400044400000244420000000000cbbbbcbbbbbccccc50000000a5ccbbb55000000000000000000099999a995000bbbbbbcccccccccccbbbbbbbb3333333
044440000440000000222000000000001cccbbbbbbbbccc500000000a95cbb50000000000000000000999999a5551000bccccbcccccccccccbbbbbbbbb333333
000000000000000000000000000000000ccccbbbbbbbbb50000000000a5555500000000000000000a9a9aa9995333000bcccccccccccccccccbbbbbccb333333
000000000000000000000000000000000ccccbbbbbbbbb50000000000000000000000000000000aaa99a9a5553333300bbbccccccccccccccccbbbcccb333333
0000000000000000000000000000000001cccbbbbbbbbb5000000050000000000000000000009aa9aa9995b333333300cbbbcccbbccccccccccccccc11333333
0000000000000000000000000000000000ccccbbbbbbbbc5000003c50000000000000000000aaaaa9a555bbb33333300cbbbbcbbbbbcccccccccccccc1333333
00000000000000000000000000000000001cccccbbbbbb5000003bb500000000000000000009aaaa55bbbccb333333001cccbbbbbbbbccccccccccc111333331
0000000000000000000000000000000000011ccccbbbbc500003bbbb5000000000000000000aaaa5cbbbcccb333333000ccccbbbbbbbbbbcccccccc111333330
00000000000000000000000000000000000011c1c33bbc50003bb5555000000000000000000aa95ccccccc11333333000ccccbbbbbbbbbbcccccccc111333310
0000000000000000000000000000000000000111113311500055500000000000000000000000995cccccccc13333330001cccbbbbbbbbbbcccc1cc1111333310
0000000000000000000000000000000000000011113311500000000000000000000000000000a5ccccccc1113333310000ccccbbbbbbbbccccc1111111133100
000000000000000000000000000000000000000111133500000000000000955599000000000095ccccccc11133333000001cccccbbbbbbcccc11111111111100
000000000000000000000000000000000000000001111500000000000000951c559999900000a5ccccccc1113333100000011ccccbbbbcc1c111111111111000
000000000000000000000000000000000000000000005500000000000000a51111555555900995ccc1cc111133331000000011c1c33bbc111111111111110000
000000000000000000000000000000000000000000000000000000000009a51111111111550995ccc11111111331000000000111113311111111111111100000
00000000000000000000000000000000000000000000000000000000000a9511111111111009555c111111111111000000000011113311111111111111000000
00000000000000000000000000000000000000000000000000000000000951111111111100000005555111111110000000000001111331111111111110000000
00000000000000000000000000000000000000000000000000000000000957711777650000000000000555511100000000000000011111771177765000000000
00000000000000000000000000000000000000000000000000000000000057677660000000000000000000055000000000000000000056767766000000000000
__gff__
0000000000000000010101000000000000000000000101010100000000000000020000000000010100000000000000000000000000000101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
1818181800000000000000000000000018181818181818181818181818181818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1818000000000000000000000000000018181818180000000000001818181818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1800000000000000000000000000000018181800000000000000000000181818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1800000000000000000000000000000018180000000000000000000000001818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018180000000000000000000000001818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018180000000000000000000000001818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018180000000000000000000000001818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018181800000000000000000000181818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018181818180000000000001818181818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000018181818181818181818181818181818000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
4901000012240152301523014230122300f2300c22009220072200622004220032200221002210012100021001210002000020000200002000020000200002000560005600046000360002600016000060000000
0002000026610296102a6202c6202d6202e6302e6302e6302c6202b620296202862026620236201f6101861015610126100e6100a610086100661005610046100361002610026100261002610026100261002610
0003000034650346603366033670306702d6702a67027670266702467022670206601e6601d6601c6601b6601a6501865017650176501665016640166401664016640156401464012640106300d6200961005600
180e00001662016620166201562015620146201362012610126101161010610106100f6100e6100d6100d6100c6100b6100a6100a6100a6100961009610086100761007610066100661006610056100561005610
0003000034620346203363033630306302d6302a63027630266202462022620206201e6201d6101c6101b6101a6101861017610176101661016610166101661016610156101461012610106100d6100961005600
000a00003305000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000180501f050240500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001905020050250500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001a05021050260500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001b05022050270500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000700001c05023050280502800029000290002900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001500001d0502905024050210501d0501d000000000a0001a0001b0001d0001d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0015000011120111200c1400c14005150051000510029000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0015000011120111200c1400c14005150051000510029000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01140000151501a1501d1502115026150211501d1501c15015150181501a1501c150151501515000100101001315017150181501a1501f1501a150171501710015150191501a1501c150211501c1501515015150
001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500001567016670126600b6400c630000000000020600000000000000000000001260000000000001d60032650316502465014650006000c60015600136000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011800202107000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d1100020000730000300073000030007300003000730000300073000030007300003000730000300073000030007300003000730000300073000030007300003000730000300073000030007300003000731d605
d1100000000730007300073000030007300003000730000300073000030007300003000730007300073000730007300003000730000300073000030007300003000730007300073000030007300073000731d605
0110000000000000001c6750000000000000001c6750000000000000001c6750000000000000001c6750000000000000001c6750000000000000001c6750000000000000001c6750000000000000001c67500000
__music__
00 25276844
00 26274344

