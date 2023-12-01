pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- astroy
-- by felix and mathias

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
	srand(73)

	poke(0x5F5C, 255) -- set btnp to never repeat

	initialize_pause_screen()
	init_starfield()
end

gameover_t = 0
winner = nil
max_wins = 5

function endgame_logic()
	gameover_t += 1
	if gameover_t > 60 then
		-- next round
		gameover_t = 0
		
		if winner != nil and winner.wins >= max_wins then
			game_state = "title"
			players = {}
			sfx(sounds.game_win_lead)
			sfx(sounds.game_win_bass)
		else
			load_random_level()
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

-- called by pico-8 60 times per sec
function _update60()
	if game_state == "title" then
		if update_pause_screen() then
			load_random_level()
			game_state = "level"
		end
	else
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
	update_particles()
	update_starfield()
end

-- called once per frame by pico-8
function _draw()
	cls()
	fillp()

	draw_starfield()

	if game_state == "title" then
		draw_pause_screen()
	else
		draw_particles()

		-- draw bodies
		for body in all(bodies) do
			if body.type == PLANET then
				if fget(body.sprite, 0) then -- fragment sprite flag
					local tile = flr(body.rand * 4)
					local tile_x = tile % 2
					local tile_y = flr(tile / 2)
					sspr((body.sprite % 16) * 8 + tile_x * 4, flr(body.sprite / 16) * 8 + tile_y * 4, 4, 4, body.x - 3, body.y - 3)
				elseif fget(body.sprite, 1) then -- big sprite flag
					spr(body.sprite, body.x - 6, body.y - 6, 2, 2)
				else
					spr(body.sprite, body.x - 3, body.y - 3)
				end
			elseif body.type == PROJECTILE then
				-- draw_projectile(body)
				spr(body.sprite, body.x - 3, body.y - 3)
			elseif body.type == SUN then
				draw_sun(body.x, body.y)
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
end

-->8
-- players

shoot_delay = 0.3
shoot_strength = 50
recoil_strength = 280

players = {}

function add_player_body(player, x, y)
	local body = body_create(x, y)
	body.mass = 6
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
	-- if (now - player.last_shot_t < shoot_delay) return

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

-- local DYNAMIC = false
-- local STATIC = true

function body_create(x, y)
	x = x or 0 -- default pos
	y = y or 0
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
	if fget(body.sprite, 0) then return end

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
		frag_body.sprite = body.sprite + 4
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
	p.sprite = 26

	return p
end

function remove_dead_projectiles()
   for _, body in ipairs(bodies) do
		if body.type == PROJECTILE and out_of_bounds(proj.pos) then 
			del(bodies, body)
		end
   end
end

local dt = 1 / 60
function update_bodies()
	-- dynamic bodies attract to static bodies and each other
	local collisions = {}
	
	for i = 1, #bodies do
		local b1 = bodies[i]
		for j = i + 1, #bodies do
			local b2 = bodies[j]

			local dx = b2.x - b1.x
			local dy = b2.y - b1.y

			dx = dx >> 0x5
			dy = dy >> 0x5

			local dsq = dx*dx + dy*dy
			local d = sqrt(dsq)

			-- if d > gravity_range then return end

			if (d << 0x5) <= b1.radius + b2.radius then
				if b2.type > b1.type then
					add(collisions, { first = b1, second = b2 })
				else
					add(collisions, { first = b2, second = b1 })
				end
			end

			local a1 = b1.static and 0 or gravity_constant * b2.mass / dsq
			local a2 = b2.static and 0 or gravity_constant * b1.mass / dsq
			b1.ddx += (dx / d) * a1
			b1.ddy += (dy / d) * a1
			b2.ddx -= (dx / d) * a2
			b2.ddy -= (dy / d) * a2
		end
	end

	for pair in all(collisions) do
		local b1 = pair.first
		local b2 = pair.second

		if b1.type == SUN and b2.type == SUN then
			-- do nothing
		elseif b2.type == SUN then
			-- particle effects
			local dx = b1.x - b2.x
			local dy = b1.y - b2.y
			particle_sun_emit(b2.x, b2.y, dx, dy)

			-- play sound
			sfx(sounds.sun_swallow)

			body_destroy(b1)
		else
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

function make_particle(type, col, x, y)
	local particle = {
		type = type,
		col = col,
		x = x,
		y = y,
		dx = 0,
		dy = 0,
		drag = 0.95,
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
		if particle.age > particle.life then
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
	for i = 1, 16 do
		-- local speed = random_btwn(0.06, 0.2)
		local speed_scale = rnd(0.5) + 0.1
		local col = rnd(2) + 8
		local particle = make_particle(PARTICLE_SPARK, col, x, y)
		particle.dx = dx * speed_scale + random_btwn(-0.2, 0.2)
		particle.dy = dy * speed_scale + random_btwn(-0.2, 0.2)
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

function draw_particles()
	for particle in all(particles) do
		if particle.type == PARTICLE_SPARK then
			pset(particle.x, particle.y, particle.col)
		elseif particle.type == PARTICLE_SMOKE then
			circfill(particle.x, particle.y, 4 - 4 * (particle.age / particle.life), particle.col)
		end
	end
end

-->8
-- levels

NUM_LEVELS = 1

function load_random_level()
	printh("load random level")
	init_level(flr(rnd(NUM_LEVELS)) + 1)
end

function init_level(level)
	printh("load level " .. level)
	bodies = {}

	for player in all(players) do
		player.alive = true
		player.last_shot_t = time() + 1
	end

	if level == 1 then
		-- two planets
		local b1 = add_player_body(players[1], 32, 32)
		local b2 = add_player_body(players[2], 96, 96)

		-- local sun = add_sun(64, 64, 16, 0.8)
		-- b1.dx = -4
		-- b1.dy = 4
		-- b1.vel = tangent_vel(b1, b2)
		-- b2.vel = tangent_vel(b2, b1)
	end
	-- elseif level == 2 then
	-- 	-- sun and two planets
		
	-- 	local sun = add_sun(makevec2d(0, 0), 16, 0.8)

	-- 	local b1 = add_player_body(players[1], makevec2d(-4, -4), makevec2d(0, 0))
	-- 	local b2 = add_player_body(players[2], makevec2d( 4,  4), makevec2d(0, 0))
	-- 	b1.vel = tangent_vel(b1, sun)
	-- 	b2.vel = tangent_vel(b2, sun)
	-- elseif level == 3 then
	-- 	-- sun, mercury and two planets
		
	-- 	local sun = add_sun(makevec2d(0, 0), 16, 0.8)

	-- 	local mercury = add_planet(makevec2d(0, -2), 0.2, 0.2)
	-- 	mercury.vel = tangent_vel(mercury, sun)
	-- 	mercury.sprite = 33

	-- 	local b1 = add_player_body(players[1], makevec2d(-5, -5), makevec2d(0, 0))
	-- 	local b2 = add_player_body(players[2], makevec2d( 5,  5), makevec2d(0, 0))
	-- 	b1.vel = tangent_vel(b1, sun)
	-- 	b2.vel = tangent_vel(b2, sun)
	-- elseif level == 4 then
	-- 	-- two suns
		
	-- 	local sun1 = add_sun(makevec2d( 4, 0), 16, 0.8)
	-- 	local sun2 = add_sun(makevec2d(-4, 0), 16, 0.8)

	-- 	add_player_body(players[1], makevec2d(-1, -1), makevec2d(-2.2, -3.5), 0)
	-- 	add_player_body(players[2], makevec2d(1, 1), makevec2d(2.2, 3.5), 0)
	-- elseif level == 5 then
	-- 	-- sun and moons
		
	-- 	local sun = add_sun(makevec2d(0, 0), 16, 0.8)

	-- 	local b1 = add_player_body(players[1], makevec2d( 5, -5), makevec2d(0, 0), 0)
	-- 	local b2 = add_player_body(players[2], makevec2d(-5,  5), makevec2d(0, 0), 0)

	-- 	local moon1 = add_planet(b1.pos + makevec2d(-1, 0), 0.1, 0.2)
	-- 	local moon2 = add_planet(b2.pos + makevec2d( 1, 0), 0.1, 0.2)

	-- 	b1.vel = tangent_vel(b1, sun)
	-- 	b2.vel = tangent_vel(b2, sun)
	-- 	moon1.vel = tangent_vel(moon1, b1) + tangent_vel(moon1, sun)
	-- 	moon2.vel = tangent_vel(moon2, b2) + tangent_vel(moon2, sun)
	-- 	moon1.sprite = 18
	-- 	moon2.sprite = 18
	-- elseif level == 6 then
	-- 	-- sun, saturn and other planet
		
	-- 	local sun = add_sun(makevec2d(0, 0), 16, 0.8)

	-- 	local alien = add_planet(makevec2d(-1.2, -1.2), 1, 0.2)
	-- 	alien.vel = tangent_vel(alien, sun)
	-- 	alien.sprite = 2

	-- 	local saturn = add_planet(makevec2d(7, 7), 12, 0.4)
	-- 	saturn.vel = tangent_vel(saturn, sun)
	-- 	saturn.sprite = 3

	-- 	local b1 = add_player_body(players[1], makevec2d( 4.5, -4.5), makevec2d(0, 0), 0)
	-- 	local b2 = add_player_body(players[2], makevec2d(-4.5,  4.5), makevec2d(0, 0), 0)
	-- 	b1.vel = tangent_vel(b1, sun)
	-- 	b2.vel = tangent_vel(b2, sun)
	-- elseif level == 7 then
	-- 	-- sun, saturn and other planet
		
	-- 	local sun = add_sun(makevec2d(0, 0), 16, 0.8)

	-- 	local comet = add_planet(makevec2d(0, 10), 1, 0.2)
	-- 	comet.vel = tangent_vel(comet, sun) * 0.5 + makevec2d(-0.5, 0)
	-- 	comet.sprite = 50

	-- 	local venus = add_planet(makevec2d(0, 1.5), 1.5, 0.2)
	-- 	venus.vel = tangent_vel(venus, sun)
	-- 	venus.sprite = 49

	-- 	local b1 = add_player_body(players[1], makevec2d(-5.6, -5.6), makevec2d(0, 0), 0)
	-- 	local b2 = add_player_body(players[2], makevec2d( 5.6,  5.6), makevec2d(0, 0), 0)
	-- 	b1.vel = tangent_vel(b1, sun)
	-- 	b2.vel = tangent_vel(b2, sun)
	-- elseif level == 8 then
	-- 	-- close and far orbit + satellite
		
	-- 	local sun = add_sun(makevec2d(0, 0), 16, 0.8)

	-- 	local satellite = add_planet(makevec2d(0, -7), 1, 0.2)
	-- 	satellite.vel = tangent_vel(satellite, sun)
	-- 	satellite.sprite = 65

	-- 	local b1 = add_player_body(players[1], makevec2d(0, 2), makevec2d(0, 0), 0)
	-- 	local b2 = add_player_body(players[2], makevec2d(0, 7.5), makevec2d(0, 0), 0)
	-- 	b1.vel = tangent_vel(b1, sun)
	-- 	b2.vel = tangent_vel(b2, sun)
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

-->8
-- pause menu

local sprite_choices = {-- list of available sprite_choices
{ id = 1,  chosen = false },
{ id = 17, chosen = false },
{ id = 33, chosen = false },
{ id = 49, chosen = false }
} 

local UNAVAILABLE_SPRITE = 62
local pause_screen_players = {} 
local num_players = 2

local player_marker_colors = { 8, 12, 11, 14 }
local player_marker_shadow_colors = { 2, 1, 3, 13 }

function initialize_pause_screen()
	for i = 1, num_players do
		add(pause_screen_players, {
			player_index = i - 1,
			choice_index = (i - 1) % #sprite_choices + 1,
			commited = false,
			marker_color = player_marker_colors[i],
			marker_shadow_color = player_marker_shadow_colors[i]
		})
	end
end

function update_pause_screen()
	for player in all(pause_screen_players) do
		local choiceidx = player.choice_index
		
		if btnp(5, player.player_index) then 
			local choice = sprite_choices[choiceidx]
			if not choice.chosen and not player.commited then 
				choice.chosen = true
				player.commited = true
			elseif choice.chosen and player.commited then
				choice.chosen = false
				player.commited = false
			end
		end
		
		if not player.commited and btnp(2, player.player_index) then
			local idx = choiceidx - 1
			player.choice_index = (idx - 1) % #sprite_choices + 1 -- wrap around
		elseif not player.commited and btnp(3, player.player_index) then
			local idx = choiceidx + 1
			player.choice_index = (idx - 1) % #sprite_choices + 1
		end
	end
	
	local num_commited = 0
	for plr in all(pause_screen_players) do
		if plr.commited then num_commited += 1 end
	end
	
	if btn() & 0x1010 > 0 -- detect any player pressed o
			and num_commited > 1 then
		for player in all(pause_screen_players) do
			if player.commited then
				add_player(player.player_index, sprite_choices[player.choice_index].id, player.marker_color, player.marker_shadow_color)
			end
		end
		return true
	else
		return false
	end
end 

local considering_color = 7
local not_considering_color = 7
local picked_color = 9

function draw_pause_screen()
	color(7)
	cursor(16, 104)
	print("press 🅾️ to choose planet")
	cursor(16, 114)
	print("press ❎ to begin")
	
	local slot_width = 128 / (num_players + 1)
	
	local x = -slot_width * (num_players - 1) / 2 + 64
	local y = 72
	
	local box_width = 15
	local box_height = 15
	
	local topy = y - box_height * ((#sprite_choices + 1) / 2)
	
	for playeridx, player in ipairs(pause_screen_players) do
		
		local leftx = x - box_width / 2
		local rightx = leftx + box_width
		local boty = topy + box_height * (#sprite_choices + 1)
		
		if playeridx == 1 then 
			cursor(leftx - 18, topy - 10)
		end
		
		cursor(leftx + 4, topy - 10)
		print("p" .. player.player_index + 1, 7)
		
		-- cursor(leftx + 3, topy + box_height * 4 + 3)
		-- print(player_wins[playeridx] .. "★", 10)
		
		local tlx = leftx 
		local tly = topy
		
		line(leftx, topy, rightx, topy, not_considering_color)
		
		for i, sprite in ipairs(sprite_choices) do
			local brx = tlx + box_width
			local bry = tly + box_height
			
			if i == player.choice_index then
				local color = 0
				if player.commited then color = player.marker_color 
				else color = considering_color end 
				
				rect(tlx, tly, brx, bry, color)
				
				pal(12, player.marker_color)
				pal(1, player.marker_shadow_color)
				spr(61, tlx + 18, tly + 4)
				pal()
			else
				line(tlx, tly + 1, tlx, bry, not_considering_color)
				line(brx, tly + 1, brx, bry, not_considering_color)
				line(tlx, bry, brx, bry, not_considering_color)
			end
			
			local id = sprite.id
			if sprite.chosen and not (player.commited and player.choice_index == i)  then
				id = UNAVAILABLE_SPRITE
			end
			
			spr(id, tlx + 4, tly + 4)
			
			tly += box_height
		end
		
		x += slot_width
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

-- local vertical_proj = 25
-- local horizontal_proj = 41
-- local diagonal_proj = 57
-- function draw_projectile(body)
-- 	-- local dir = body.vel:unit()

-- 	-- local cx = nil
-- 	-- local cy = nil
-- 	-- local closest_dot = -20000
-- 	-- for x = -1, 1 do
-- 	-- 	for y = -1, 1 do 
-- 	-- 		if x != 0 or y != 0 then
-- 	-- 			local u = makevec2d(x, y):unit()
-- 	-- 			local dot = dir.x * u.x + dir.y * u.y
-- 	-- 			if dot > closest_dot then
-- 	-- 				cx = x
-- 	-- 				cy = y
-- 	-- 				closest_dot = dot
-- 	-- 			end
-- 	-- 		end
-- 	-- 	end
-- 	-- end

-- 	-- local sprite = 1
-- 	-- if abs(cx) == abs(cy) then sprite = diagonal_proj 
-- 	-- elseif abs(cx) > abs(cy) then sprite = horizontal_proj
-- 	-- else sprite = vertical_proj end

-- 	spr(body.sprite, body.x - 3, body.y - 3)
-- end

function draw_aiming_arrows(player)
	local b = player.body

	local sx = 72
	local sy = 0

	if player.aim_x != 0 and player.aim_y != 0 then
		sx = 72
		sy = 4
	elseif player.aim_x != 0 then
		sx = 72
		sy = 0
	elseif player.aim_y != 0 then
		sx = 76
		sy = 0
	else
		return
	end

	pal(8, player.fg_color)
	pal(2, player.bg_color)

	local arrow_x = b.x + flr(5 * player.aim_x - 0.5)
	local arrow_y = b.y + flr(5 * player.aim_y - 0.5)

	sspr(sx, sy, 4, 4,
		 arrow_x, arrow_y, 4, 4,
		 player.aim_x < 0, player.aim_y < 0)

	pal()
end

-- function integer_digits(num)
-- 	local count = 0
-- 	num = flr(num)
-- 	while num != 0 do
-- 		num -= num % 10
-- 		num /= 10
-- 		count += 1
-- 	end
-- 	return count
-- end

local diagonal_ob_arrow_x = 88
local diagonal_ob_arrow_y = 24
local vertical_ob_arrow_x = 96
local vertical_ob_arrow_y = 24
local horizontal_ob_arrow_x = 104
local horizontal_ob_arrow_y = 24
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
	local sz = ceil((1 - t) * 8 + t * 3)

	if player.out_of_bounds_time >= 30 and flr(player.out_of_bounds_time / ob_blink_freq) % 2 == 0 then 
		pal(12, 10)
		pal(1, 7)
	else 
		pal(12, player.fg_color)
		pal(1, player.bg_color)
	end

	if player.out_of_bounds_time >= 30 and player.out_of_bounds_time % (ob_blink_freq * 2) == 0 then
		sfx(sounds.out_of_bounds_beep) 
	end

	sspr(spritex, spritey, 8, 8, px - sz / 2, py - sz / 2, sz, sz, px > 64, py > 64)
	pal()
end

function draw_winner()
	assert(winner != nil)

	local star_width = 6
	
	local lx = winner.body.x - (winner.wins / 2) * star_width
	local y = winner.body.y - 7
	lx += 1
	for i = 1, winner.wins do
		spr(13, lx, y)
		lx += star_width
	end
end

star_particles = {}
function init_starfield()
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
		-- if particle.pos.x < -64 then
		-- 	particle.pos.x += 128
		-- 	particle.old.x += 128
		-- end
		-- if particle.pos.x > 64 then
		-- 	particle.pos.x -= 128
		-- 	particle.old.x -= 128
		-- end
		-- if particle.pos.y < -64 then
		-- 	particle.pos.y += 128
		-- 	particle.old.y += 128
		-- end
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
0000000000000000000000000000000000000000003c00cc002d00dd00990ff9000000000280000000000000000000000000000000a000000000000000000000
0000000000c7cc0000dddd000000000000000000dccd03cddddd02ddffffd99d0000000000282002000000000000000000000000aaaaa0000000000000000000
007007000bcccbc00ddd12d000000000000000000dd00dc00dd00dd0dffddff000000000002882280000000000000000000000000aaa00000000000000000000
000770000bbcbbb00212ddd0000000000000000000000dd000000dd00dd0ddd000000000028008800000000000000000000000000a0a00000000000000000000
000770000bccbbc00dddd120000000ffff000000c0000000d0000000f900fff00000000000000000000000000000000000000000000000000000000000000000
007007000ccccbc0022dddd000000ffff9900000cc00d3c0dd00d2d0f9f0d99f0000000000020000000000000000000000000000000000000000000000000000
0000000000c77c000022220000ddf9999fffdd00d3c00dcdd2d00ddddffd0dff0000000000280000000000000000000000000000000000000000000000000000
0000000000000000000000000d00ffffffff00d00ddd00d00ddd00d00ddd00d00000000002880000000000000000000000000000000000000000000000000000
00000000000000000000000001ddd99f999ddd100028008800560066000000000000000006600000000000000000000000000000000000000000000000000000
00000000002228000000000000111dddddd11100d88d028dd66d056d000000000000000006600000000000000000000000000000000000000000000000000000
0000000008888880000660000000f111111f00000dd00d800dd00d6000000000000000000aa00000000000000000000000000000000000000000000000000000
000000000228822000676500000009fffff0000000000dd000000dd000000000000000000a0000000007e0000000000000000000000000000000000000000000
000000000888228000656700000000999f0000008000000060000000000000000000000000000000000e20000000000000000000000000000000000000000000
00000000028888800006600000000000000000008800d2806600d560000000000000000000000000000000000000000000000000000000000000000000000000
0000000000228800000000000000000000000000d2800d8dd5600d6d000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000ddd00d00ddd00d0000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000d60066003b00bb00dd02dd0000000000000000000000000000000000000000000000000000000000000000
000000000066660000b22d000000000000000000d66d0d6ddbbd03bd1c22d12d000000000a660000000000000000000000000000000000000000000000000000
000000000d6d6d600bd2d3b000000000000000000dd00d600dd00db0d11dd11000000000aa660000000000000000000000000000000000000000000000000000
000000000dd666d00b333bb0000000000000000000000dd000000dd00dd0ddd00000000000000000000000000000000000000000000000000000000000000000
000000000dd6d66003bbb330000000c77c00000060000000b0000000c100cd200000000000000000000000000000000000000000000000000000000000000000
000000000dddd6600b33333000000cdc7cd000006600dd60bb00d3b02d10d12c0000000000000000000000000000000000000000000000000000000000000000
0000000000dd6600003d23000000cddccddc0000dd600d6dd3b00dbdd21d0d110000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000cdddccdd00000ddd00d00ddd00d00ddd00d00000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000011dddc22000000490099001c00c7000000000000000000660000000000000000000000000000000000000000000000000000
0000000000999900000000000000112212210000d99d049dd7cd017d00000000000000000a6600000000000000ccc100000cc000000c10000006600000000000
00000000099944900007700000000121111000000dd00d900dd00dc000000000000000000aa00000000000000ccc100000cccc0000cc10000060060000000000
000000000944999000c7c700000000166100000000000dd000000dd00000000000000000a0000000000000000cc100000cccccc00ccc10000606006000000000
00000000044994400c1ccc00000000000000000090000000c0000000000000000000000000000000000000000c100000011111100ccc10000600606000000000
0000000004444440c101100000000000000000009900d490c700d17000000000000000000000000000000000010000000000000000cc10000060060000000000
000000000044440010c100000000000000000000d4900d9dd1700dcd000000000000000000000000000000000000000000000000000c10000006600000000000
00000000000000000c10000000000000000000000ddd00d00ddd00d0000000000000000000000000000000000000000000000000000000000000000000000000
000000000000800000000000000000000000000000006330000000000000000000099990009999900099999009999900009999000099099001ddd10000000000
000000006000d0600000000000000000000000005600005000000000000000000099999009999990099999900999999009999990009909900dd6dd1000000000
0000000030666030000000000000000000000000d500056000000000000000000099099009990000000990000000099009909990009999000d611d1000000000
0000000035d66530000000000000000000000000dd6000d00000000000000000044404400444440000444000000444004440444000444000dd61dd1000000000
0000000030ddd0300000000000000000000000000000000000000000000000000440044000044400004400000004400044404400004400001ddddd1000000000
00000000d00500d00000000000000000000000000d000050000000000000000044400440444444000444000000004400444444000444000001ddd10000000000
0000000000dd600000000000000000000000000005500dd600000000000000004400044044444000044000000000440004444000044000000011100000000000
000000000d5556000000000000000000000000000566065000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000a9aa900000000000006cccccc10000000000000000000000000000000000000000000006cccccc10000000000000000000000006cccccc1000000000000
00099a555550000000001577ccccbcccc30000000000000000000000000000000000000001577ccccbcccc30000000000000000001577ccccbcccc3000000000
005555bbbb500000005cc67cccccbbcbbbb3000000000000000000000000000000000001cc67cccccbbcbbbb3000000000000001cc67cccccbbcbbbb30000000
00bbbbbbbcc500000095cc6cccccccbbbbbb30000000000000000000000000000000003cccc6cccccccbbbbbb30000000000003cccc6cccccccbbbbbb3000000
03bbbbbcccc50000009555cccccccccbbbbb3100000000000000000000000000000003bbbcccccccccccbbbbb3100000000003bbbcccccccccccbbbbb3100000
0bbbbbbccccc5000000995cccccccbbbccbb331000000000000000000000000000003bbbbbbcccccccbbbccbb331000000003bbbbbbcccccccbbbccbb3310000
0bbbbbbcccccc500000095cccccccbbcccbb11330000000000000000000000000003bbbbbbbcccccccbbcccbb11330000003bbbbbbbcccccccbbcccbb1133000
3bbbbbbcccccc500000095cccccccccbbcccc133300000000000000000000000003bbbbbbbccccccccccbbcccc133300003bbbbbbbccccccccccbbcccc133300
bbbbbbccccccc50000000955cccccbbbbbccb31330000000000000000000000000bbbbbbbcccccccccbbbbbccb31330000bbbbbbbcccccccccbbbbbccb313300
bccccbcccccccc5000000995cccccbbbbbbbbb3315000000000000000000000003bbbbbcccccccccccbbbbbbbbb3313003bbbbbcccccccccccbbbbbbbbb33130
bcccccccccccccc5000000a5ccccbbbbbbbbb3355000000000000000000000000bbbbbbccccccccccbbbbbbbbb3331100bbbbbbccccccccccbbbbbbbbb333110
bbbccccccccccccc500000aa5cccbbbbbb55b5500000000000000000999000000bbbbbbccccccccccbbbbbbbbbb333300bbbbbbccccccccccbbbbbbbbbb33330
cbbbcccbbccccccc5000000095ccbbbbb50050000000000000000099999900003bbbbbbccccccccccbbbbbbbbb3333333bbbbbbccccccccccbbbbbbbbb333333
cbbbbcbbbbbccccc50000000a5ccbbb55000000000000000000099999a995000bbbbbbcccccccccccbbbbbbbb3333333bbbbbbcccccccccccbbbbbbbb3333333
1cccbbbbbbbbccc500000000a95cbb50000000000000000000999999a5551000bccccbcccccccccccbbbbbbbbb333333bccccbcccccccccccbbbbbbbbb333333
0ccccbbbbbbbbb50000000000a5555500000000000000000a9a9aa9995333000bcccccccccccccccccbbbbbccb333333bcccccccccccccccccbbbbbccb333333
0ccccbbbbbbbbb50000000000000000000000000000000aaa99a9a5553333300bbbccccccccccccccccbbbcccb333333bbbccccccccccccccccbbbcccb333333
01cccbbbbbbbbb5000000050000000000000000000009aa9aa9995b333333300cbbbcccbbccccccccccccccc11333333cbbbcccbbccccccccccccccc11333333
00ccccbbbbbbbbc5000003c50000000000000000000aaaaa9a555bbb33333300cbbbbcbbbbbcccccccccccccc1333333cbbbbcbbbbbcccccccccccccc1333333
001cccccbbbbbb5000003bb500000000000000000009aaaa55bbbccb333333001cccbbbbbbbbccccccccccc1113333311cccbbbbbbbbccccccccccc111333331
00011ccccbbbbc500003bbbb5000000000000000000aaaa5cbbbcccb333333000ccccbbbbbbbbbbcccccccc1113333300ccccbbbbbbbbbbcccccccc111333330
000011c1c33bbc50003bb5555000000000000000000aa95ccccccc11333333000ccccbbbbbbbbbbcccccccc1113333100ccccbbbbbbbbbbcccccccc111333310
00000111113311500055500000000000000000000000995cccccccc13333330001cccbbbbbbbbbbcccc1cc111133331001cccbbbbbbbbbbcccc1cc1111333310
00000011113311500000000000000000000000000000a5ccccccc1113333310000ccccbbbbbbbbccccc111111113310000ccccbbbbbbbbccccc1111111133100
0000000111133500000000000000955599000000000095ccccccc11133333000001cccccbbbbbbcccc11111111111100001cccccbbbbbbcccc11111111111100
0000000001111500000000000000951c559999900000a5ccccccc1113333100000011ccccbbbbcc1c11111111111100000011ccccbbbbcc1c111111111111000
0000000000005500000000000000a51111555555900995ccc1cc111133331000000011c1c33bbc111111111111110000000011c1c33bbc111111111111110000
0000000000000000000000000009a51111111111550995ccc1111111133100000000011111331111111111111110000000000111113311111111111111100000
000000000000000000000000000a9511111111111009555c11111111111100000000001111331111111111111100000000000011113311111111111111000000
00000000000000000000000000095111111111110000000555511111111000000000000111133111111111111000000000000001111331111111111110000000
00000000000000000000000000095771177765000000000000055551110000000000000001111177117776500000000000000000011111771177765000000000
00000000000000000000000000005767766000000000000000000005500000000000000000005676776600000000000000000000000056767766000000000000
__gff__
0000000200010101000000000000000000000000000101010000000000000000000000020001010100000000000000000000000000010101000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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

