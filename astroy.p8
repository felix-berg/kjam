pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- astroy
-- by felix and mathias

#include vec2d.lua
#include body.lua
#include particle.lua
#include util.lua
#include pausescreen.lua

game_state = "title"

local sounds = {
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

local world_scale = 8
local world_size = 128 / world_scale
local world_tl = makevec2d(-world_size, -world_size) / 2
local world_br = makevec2d( world_size,  world_size) / 2

function screen_space(pos)
	return pos * world_scale
end

-- physics entities
local bodies = {}

-- objects with references to physics bodies
local players = {}

local projectile_mass = 1.5
local projectile_radius = 0.2
function add_projectile(pos, vel)
	local p = make_body(pos)
	p.vel = vel:copy()
	p.mass = projectile_mass
	p.radius = projectile_radius
	p.type = PROJECTILE
	p.is_static = DYNAMIC
	p.sprite = 5

	add(bodies, p)
end

function out_of_bounds(pos, tl, br)
	return pos.x < tl.x or pos.x > br.x or pos.y < tl.y or pos.y > br.y
end

function projectile_should_die(proj)
	return out_of_bounds(proj.pos, world_tl - (world_br - world_tl) * 0.25, world_br + (world_br - world_tl) * 0.25)
end

function remove_dead_projectiles()
   for _, body in ipairs(bodies) do
		if body.type == PROJECTILE and projectile_should_die(body) then 
			del(bodies, body)
		end
   end
end

function add_fragment(pos, vel, mass, radius, sprite)
	local fragment_body = make_body(pos)
	fragment_body.vel = vel:copy()
	fragment_body.mass = mass
	fragment_body.radius = radius
	fragment_body.type = FRAGMENT
	fragment_body.is_static = DYNAMIC
	fragment_body.sprite = sprite
	add(bodies, fragment_body)
end

local fragment_max_spawn_distance = 2
local min_explosion_strength = 1
local max_explosion_strength = 3
local angle_spread = 0.1
local mass_falloff = 100
local radius_multiplier = 0.1

-- add exploding fragments of this body exploding into the "bodies" table
function generate_fragments(body, fragment_count)
	-- each fragment has a nth size and radius
	local mass = body.mass / (fragment_count * mass_falloff)
	local radius = radius_multiplier * body.radius / fragment_count 
	
	local min_dist = radius + body.radius

	local da = 1 / fragment_count
	for i = 1, fragment_count do
		local angle = da * i
		
		angle += random_btwn(-angle_spread, angle_spread)
		dist = min_dist -- random_btwn(min_dist, fragment_max_spawn_distance)

		local angle_vec = makevec2d(cos(angle), sin(angle))
		angle_vec:normalize()

		local pos_offset = angle_vec * dist
		local exp_strength = random_btwn(min_explosion_strength, max_explosion_strength)
		local vel = angle_vec * exp_strength

		add_fragment(body.pos + pos_offset, vel, mass, radius, body.sprite + 4)
	end
end

function explode(body)
	local colors = {5, 5, 8, 8, 9, 9, 10, 10}
	for i = 1, 8 do
		local prange = 2 * body.radius
		local vrange = 5 * body.radius
		local lifetime = random_btwn(body.radius * 100, body.radius * 300)

		local pos = body.pos + makevec2d(random_btwn(-prange, prange), random_btwn(-prange, prange))
		make_particle(PARTICLE_SMOKE, colors[i], pos, makevec2d(random_btwn(-vrange, vrange), random_btwn(-vrange, vrange)), lifetime)
	end
end

function play_collision_sfx(b1, b2)
	if b1.type == SUN or b2.type == SUN then
		sfx(sounds.sun_swallow)
	elseif b1.type == PLANET or b2.type == PLANET then
		sfx(sounds.planet_explosion)
		sfx(sounds.planet_explosion_rumble)
	elseif b1.type == PROJECTILE then
		sfx(sounds.projectile_explosion)
	end
end

function handle_body_collision(b1, b2)
	if (b1.type != SUN) del(bodies, b1)
	if (b2.type != SUN) del(bodies, b2)

	if (b1.type == PLANET and b2.type != SUN) generate_fragments(b1, 3)
	if (b2.type == PLANET and b1.type != SUN) generate_fragments(b2, 3)

	if b1.type == SUN then
		local dir = b2.pos - b1.pos
		local spread = 2
		dir:normalize()
		for i = 1, 16 do
			local vel = dir * random_btwn(4, 11)
			vel += makevec2d(random_btwn(-spread, spread), random_btwn(-spread, spread))
			make_particle(PARTICLE_SPARK, random_btwn(8, 10), b1.pos, vel, 60)
		end
	end

	if b1.type != SUN and b2.type != SUN then
		explode(b1)
		explode(b2)
	end
end

function find_player(body)
	for _, player in ipairs(players) do
		if player.body == body then
			return player
		end
	end
	return nil
end

function update_collisions()
	local collisions = {}
	
	for i = 1, #bodies do
		local b1 = bodies[i]
		for j = i + 1, #bodies do 
			local b2 = bodies[j]

			if collides(b1, b2) then 
				add(collisions, { first = b1, second = b2 })
			end
		end
	end

	for _, pair in ipairs(collisions) do
		local b1 = pair.first
		local b2 = pair.second

		handle_body_collision(b1, b2)
		play_collision_sfx(b1, b2)
		
		local p1 = find_player(b1)
		local p2 = find_player(b2)

		if p1 != nil then p1.alive = false end
		if p2 != nil then p2.alive = false end
	end
end

local player_mass = 6
local player_radius = 0.32
function add_player_body(player, pos, vel)
	local body = make_body(pos)
	body.vel = vel:copy()
	body.mass = player_mass
	body.radius = player_radius
	body.type = PLANET
	body.is_static = false
	body.sprite = player.sprite

	player.body = body

	add(bodies, body)

	return body
end

function add_player(playeridx, sprite, fg_color, bg_color)
	local player = {
		body = nil,
		index = playeridx,
		controldir = makevec2d(0, 0),
		xdown = false,
		sprite = sprite,
		alive = true,
		wins = 0,
		out_of_bounds_time = 0,
		fg_color = fg_color,
		bg_color = bg_color,
		last_shot_t = 0
	}

	add(players, player)

	return player
end

function add_planet(pos, mass, radius)
	local body = make_body(pos)
	body.mass = mass
	body.radius = radius
	body.type = PLANET
	body.is_static = DYNAMIC
	body.sprite = 1
	add(bodies, body)

	return body
end

function add_sun(pos, mass, radius)
	local body = make_body(pos)
	body.mass = mass
	body.radius = radius
	body.type = SUN
	body.is_static = STATIC
	body.sprite = 0
	add(bodies, body)

	return body
end

function x_just_pressed(player)
	if btn(controls.x, player.index) or btn(controls.o, player.index) then
		if player.xdown then return false
		else 
			player.xdown = true
			return true
		end
	else 
		player.xdown = false
		return false
	end
end

local recoil_strength = 280
function calculate_recoil(body, shootdir)
	local u = body.vel:unit() * -1
	local v = shootdir:unit()
	local dot = u.x * v.x + u.y * v.y
	local braking_coefficient = -2.5 * dot + 3.5
	return -recoil_strength * v * braking_coefficient
end

local shoot_delay = 0.3
local shoot_strength = 6
function shoot_projectile(player, shootdir)
	local now = time()
	if now - player.last_shot_t < shoot_delay then
		return
	end
	player.last_shot_t = now

	if (shootdir.x == 0 and shootdir.y == 0) return

	local body = player.body
	body:add_force(calculate_recoil(body, shootdir))

	sfx(sounds.projectile)

	-- offset projectile position by player radius in the shooting direction
	local proj_pos = body.pos + shootdir:unit() * (body.radius * 2.01) 
	local vel = shootdir * shoot_strength 
	add_projectile(proj_pos, vel)
end

function update_player_controls()
	for _, player in ipairs(players) do
		if player.alive then
			player.controldir = gamepad_dir(player.index)
			if x_just_pressed(player) then
				shoot_projectile(player, player.controldir)
			end
		end
	end
end

local out_of_bounds_death_time = 300
function update_out_of_bounds_time(player)
	if out_of_bounds(player.body.pos, world_tl, world_br) then
		player.out_of_bounds_time += 1
	else
		player.out_of_bounds_time = 0
	end
	if player.out_of_bounds_time > out_of_bounds_death_time then
		del(bodies, player.body)
		player.alive = false
	end
end

local dt = 1 / 60
function update_bodies()
	-- dynamic bodies attract to static bodies and each other
	for _, body in ipairs(bodies) do 
		if not body.is_static then 
			for _, other in ipairs(bodies) do
				if body != other and other.type != PROJECTILE then
					body:attract_to(other)
				end
			end
		end
	end

	for _, body in ipairs(bodies) do
		if (not body.is_static) body:update(dt)
	end
end

local NUM_LEVELS = 10

function init_level(level)
	bodies = {}

	for i, player in ipairs(players) do
		player.alive = true
		player.last_shot_t = time() + 1
	end

	if level == 1 then
		-- two planets
		local b1 = add_player_body(players[1], makevec2d(-4, -4), makevec2d(0, 0))
		local b2 = add_player_body(players[2], makevec2d( 4,  4), makevec2d(0, 0))
		b1.vel = tangent_vel(b1, b2)
		b2.vel = tangent_vel(b2, b1)
	elseif level == 2 then
		-- sun and two planets
		
		local sun = add_sun(makevec2d(0, 0), 16, 0.8)

		local b1 = add_player_body(players[1], makevec2d(-4, -4), makevec2d(0, 0))
		local b2 = add_player_body(players[2], makevec2d( 4,  4), makevec2d(0, 0))
		b1.vel = tangent_vel(b1, sun)
		b2.vel = tangent_vel(b2, sun)
	elseif level == 3 then
		-- sun, mercury and two planets
		
		local sun = add_sun(makevec2d(0, 0), 16, 0.8)

		local mercury = add_planet(makevec2d(0, -2), 0.2, 0.2)
		mercury.vel = tangent_vel(mercury, sun)
		mercury.sprite = 33

		local b1 = add_player_body(players[1], makevec2d(-5, -5), makevec2d(0, 0))
		local b2 = add_player_body(players[2], makevec2d( 5,  5), makevec2d(0, 0))
		b1.vel = tangent_vel(b1, sun)
		b2.vel = tangent_vel(b2, sun)
	elseif level == 4 then
		-- two suns
		
		local sun1 = add_sun(makevec2d( 4, 0), 16, 0.8)
		local sun2 = add_sun(makevec2d(-4, 0), 16, 0.8)

		add_player_body(players[1], makevec2d(-1, -1), makevec2d(-2.2, -3.5), 0)
		add_player_body(players[2], makevec2d(1, 1), makevec2d(2.2, 3.5), 0)
	elseif level == 5 then
		-- sun and moons
		
		local sun = add_sun(makevec2d(0, 0), 16, 0.8)

		local b1 = add_player_body(players[1], makevec2d( 5, -5), makevec2d(0, 0), 0)
		local b2 = add_player_body(players[2], makevec2d(-5,  5), makevec2d(0, 0), 0)

		local moon1 = add_planet(b1.pos + makevec2d(-1, 0), 0.1, 0.2)
		local moon2 = add_planet(b2.pos + makevec2d( 1, 0), 0.1, 0.2)

		b1.vel = tangent_vel(b1, sun)
		b2.vel = tangent_vel(b2, sun)
		moon1.vel = tangent_vel(moon1, b1) + tangent_vel(moon1, sun)
		moon2.vel = tangent_vel(moon2, b2) + tangent_vel(moon2, sun)
		moon1.sprite = 18
		moon2.sprite = 18
	elseif level == 6 then
		-- sun, saturn and other planet
		
		local sun = add_sun(makevec2d(0, 0), 16, 0.8)

		local alien = add_planet(makevec2d(-1.2, -1.2), 1, 0.2)
		alien.vel = tangent_vel(alien, sun)
		alien.sprite = 2

		local saturn = add_planet(makevec2d(7, 7), 12, 0.4)
		saturn.vel = tangent_vel(saturn, sun)
		saturn.sprite = 3

		local b1 = add_player_body(players[1], makevec2d( 4.5, -4.5), makevec2d(0, 0), 0)
		local b2 = add_player_body(players[2], makevec2d(-4.5,  4.5), makevec2d(0, 0), 0)
		b1.vel = tangent_vel(b1, sun)
		b2.vel = tangent_vel(b2, sun)
	elseif level == 7 then
		-- sun, saturn and other planet
		
		local sun = add_sun(makevec2d(0, 0), 16, 0.8)

		local comet = add_planet(makevec2d(0, 10), 1, 0.2)
		comet.vel = tangent_vel(comet, sun) * 0.5 + makevec2d(-0.5, 0)
		comet.sprite = 50

		local venus = add_planet(makevec2d(0, 1.5), 1.5, 0.2)
		venus.vel = tangent_vel(venus, sun)
		venus.sprite = 49

		local b1 = add_player_body(players[1], makevec2d(-5.6, -5.6), makevec2d(0, 0), 0)
		local b2 = add_player_body(players[2], makevec2d( 5.6,  5.6), makevec2d(0, 0), 0)
		b1.vel = tangent_vel(b1, sun)
		b2.vel = tangent_vel(b2, sun)
	elseif level == 8 then
		-- close and far orbit + satellite
		
		local sun = add_sun(makevec2d(0, 0), 16, 0.8)

		local satellite = add_planet(makevec2d(0, -7), 1, 0.2)
		satellite.vel = tangent_vel(satellite, sun)
		satellite.sprite = 65

		local b1 = add_player_body(players[1], makevec2d(0, 2), makevec2d(0, 0), 0)
		local b2 = add_player_body(players[2], makevec2d(0, 7.5), makevec2d(0, 0), 0)
		b1.vel = tangent_vel(b1, sun)
		b2.vel = tangent_vel(b2, sun)
	elseif level == 9 then
		-- two suns, two planets, two players
		
		local sun1 = add_sun(makevec2d(-4, -4), 16, 0.8)
		local sun2 = add_sun(makevec2d( 4,  4), 16, 0.8)

		local purple = add_planet(makevec2d(-2, -4), 3, 0.2)
		local green = add_planet(makevec2d( 2, 4), 3, 0.2)
		purple.vel = tangent_vel(purple, sun1)
		green.vel = tangent_vel(green, sun2)
		purple.sprite = 2
		green.sprite = 34

		local b1 = add_player_body(players[1], makevec2d(-4, 4), makevec2d(0, 0), 0)
		local b2 = add_player_body(players[2], makevec2d(4, -4), makevec2d(0, 0), 0)
	elseif level == 10 then
		-- figure 8

		local factor = 2.3
		local b1 = add_player_body(players[1], makevec2d(0.97, -0.243) * factor, makevec2d(0, 0), 0)
		local b2 = add_player_body(players[2], makevec2d(-0.97, 0.243) * factor, makevec2d(0, 0), 0)
		local green = add_planet(makevec2d(0, 0), 6, 0.2)

		b1.vel = makevec2d(0.932, 0.864) * factor * 0.5
		b2.vel = makevec2d(0.932, 0.864) * factor * 0.5
		green.vel = makevec2d(-0.932, -0.864) * factor
		green.sprite = 34
	end
end

function load_random_level()
	init_level(flr(rnd(NUM_LEVELS)) + 1)
end

function _init()
	camera(-64, -64)
	initialize_pause_screen()
	init_starfield()
end

local gameover_t = 0
local winner = nil
local new_level = false
local max_wins = 5

function update_endgame()
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
		for _, player in ipairs(players) do
			if player.alive then 
				player.wins += 1
				winner = player;
				sfx(sounds.round_win + winner.wins - 1)
				printh("Winner was player with controller #" .. winner.index)
			end
		end        
	end
end


local prev_num_bodies = 0
function _update60()
	if game_state == "title" then
		if update_pause_screen() then
			load_random_level()
			game_state = "level"
		end
	else
		update_player_controls()
		remove_dead_projectiles()
		update_collisions()

		-- projectile trails
		for _, body in ipairs(bodies) do
			if body.type == PROJECTILE then
				local dir = body.vel * -0.2
				dir:normalize()
				local spread = 1
				local vel = dir + makevec2d(random_btwn(-spread, spread), random_btwn(-spread, spread))
				make_particle(PARTICLE_SPARK, random_btwn(9, 11), body.pos, vel, random_btwn(10, 16))
			end
		end
	
		local players_alive = 0
		for _, player in ipairs(players) do
			players_alive = player.alive and players_alive + 1 or players_alive
		end

		if players_alive <= 1 then update_endgame() end

		for _, player in ipairs(players) do
			if (player.alive) update_out_of_bounds_time(player)
		end

		update_bodies()
		
		-- if #bodies != prev_num_bodies then
		-- 	printh("World updated, bodies:")
		-- 	for _, body in ipairs(bodies) do
		-- 		printh(" - Pos: " .. body.pos.x .. ", " .. body.pos.y .. ", radius: " .. body.radius .. ", mass: " .. body.mass .. ", type: " .. body_type_string(body))
		-- 	end
		-- 	prev_num_bodies = #bodies
		-- end
	end
	update_particles()
	update_starfield()
end

---draw---

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

local vertical_proj = 25
local horizontal_proj = 41
local diagonal_proj = 57
function draw_projectile(body)
	local dir = body.vel:unit()

	local cx = nil
	local cy = nil
	local closest_dot = -20000
	for x = -1, 1 do
		for y = -1, 1 do 
			if x != 0 or y != 0 then
				local u = makevec2d(x, y):unit()
				local dot = dir.x * u.x + dir.y * u.y
				if dot > closest_dot then
					cx = x
					cy = y
					closest_dot = dot
				end
			end
		end
	end

	local sprite = 1
	if abs(cx) == abs(cy) then sprite = diagonal_proj 
	elseif abs(cx) > abs(cy) then sprite = horizontal_proj
	else sprite = vertical_proj end

	local s = screen_space(body.pos)
	spr(sprite, s.x - 2.5, s.y - 2.5, 
		0.5, 0.5, cx < 0, cy > 0)
end

function draw_aiming_arrows(player)
	local s = screen_space(player.body.pos)
	local d = screen_space(player.controldir * 0.8)

	pal(8, player.fg_color)
	pal(2, player.bg_color)

	if player.controldir.x != 0 and player.controldir.y != 0 then
		sspr(72, 4, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, player.controldir.x < 0, player.controldir.y < 0)
		-- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
	elseif player.controldir.x != 0 then
		sspr(72, 0, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, player.controldir.x < 0)
		-- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
	elseif player.controldir.y != 0 then
		sspr(76, 0, 4, 4, s.x + d.x - 1, s.y + d.y - 1, 4, 4, false, player.controldir.y < 0)
		-- line(s.x, s.y, s.x + d.x, s.y + d.y, 7)
	end

	pal()
end

function integer_digits(num)
	local count = 0
	num = flr(num)
	while num != 0 do
		num -= num % 10
		num /= 10
		count += 1
	end
	return count
end

local diagonal_ob_arrow_x = 88
local diagonal_ob_arrow_y = 24
local vertical_ob_arrow_x = 96
local vertical_ob_arrow_y = 24
local horizontal_ob_arrow_x = 104
local horizontal_ob_arrow_y = 24
local ob_blink_freq = 30

function draw_out_of_bounds_ui(player)
	if not out_of_bounds(player.body.pos, world_tl, world_br) then return end

	local px = player.body.pos.x
	local py = player.body.pos.y
	local spritex = 0 
	local spritey = 0 

	local sprite_size = 8
	local wl_sprite_size = sprite_size / world_scale

	if px > world_tl.x and px < world_br.x then -- vertical
		spritex = vertical_ob_arrow_x
		spritey = vertical_ob_arrow_y
	elseif py > world_tl.y and py < world_br.y then --horizontal
		spritex = horizontal_ob_arrow_x
		spritey = horizontal_ob_arrow_y
	else -- diagonal
		spritex = diagonal_ob_arrow_x
		spritey = diagonal_ob_arrow_y
	end

	local w = wl_sprite_size / 2
	if     px < world_tl.x + w then px = world_tl.x + w
	elseif px > world_br.x - w then px = world_br.x - w end
	if     py < world_tl.y + w then py = world_tl.y + w
	elseif py > world_br.y - w then py = world_br.y - w end
	
	local dist = (makevec2d(px, py) - player.body.pos):size()
	local max_dist = 48
	local sz = ceil(map(clamp(dist, 0, max_dist), 0, max_dist, 8, 3))

	local c = screen_space(makevec2d(px, py))
	local s = c - makevec2d(sz, sz) / 2

	
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


	sspr(spritex, spritey, 8, 8, s.x, s.y, sz, sz, px > 0, py > 0)
	pal()
end

function draw_winner()
	assert(winner != nil)

	local star_width = 6
	
	local lx = screen_space(winner.body.pos.x) - (winner.wins / 2) * star_width
	local y = screen_space(winner.body.pos.y) - 7
	lx += 1
	for i = 1, winner.wins do
		spr(13, lx, y)
		lx += star_width
	end
end

local star_particles = {}
function init_starfield()
	local colors = {1, 6, 7}
	for i = 1, 100 do
		local x = flr(random_btwn(-64, 64))
		local y = flr(random_btwn(-64, 64))
		local r = flr(rnd(3))
		local particle = {
			pos = makevec2d(x, y),
			old = makevec2d(x, y - (r + 1) * 0.1),
			col = colors[r],
		}
	
		add(star_particles, particle)
	end
end

function update_starfield()
	for i = #star_particles, 1, -1 do
		local particle = star_particles[i]
		local vel = particle.pos - particle.old
		particle.old = particle.pos
		particle.pos += vel
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
		if particle.pos.y > 64 then
			particle.pos.y -= 128
			particle.old.y -= 128
		end
	end
end

function draw_starfield()
	for i, particle in pairs(star_particles) do
		line(particle.old.x, particle.old.y, particle.pos.x, particle.pos.y, particle.col)
	end
end

function _draw()
	cls()
	fillp()

	draw_starfield()

	if game_state == "title" then
		draw_pause_screen()
	else
		palt(0, true)

		-- draw bodies
		for _, body in ipairs(bodies) do
			local s = screen_space(body.pos)
			local r = screen_space(body.radius)
			if body.type == PLANET or body.type == FRAGMENT then
				if fget(body.sprite, 0) then -- fragment sprite flag
					local tile = flr(body.rand * 4)
					local tile_x = tile % 2
					local tile_y = flr(tile / 2)
					sspr((body.sprite % 16) * 8 + tile_x * 4, flr(body.sprite / 16) * 8 + tile_y * 4, 4, 4, s.x - 3, s.y - 3)
				elseif fget(body.sprite, 1) then -- big sprite flag
					spr(body.sprite, s.x - 6, s.y - 6, 2, 2)
				else
					spr(body.sprite, s.x - 3, s.y - 3)
				end
			elseif body.type == PROJECTILE then
				draw_projectile(body)
			elseif body.type == SUN then
				draw_sun(s.x, s.y)
			else
				circ(s.x, s.y, r)
			end
		end

		draw_particles()

		-- draw aiming arrows
		for _, player in ipairs(players) do
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
000000000228822000676500000009fffff0000000000dd000000dd000000000000000000a000000000000000000000000000000000000000000000000000000
000000000888228000656700000000999f0000008000000060000000000000000000000000000000000000000000000000000000000000000000000000000000
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
0000000000999900000000000000112212210000d99d049dd7cd017d00000000000000000a6600000000000000ccc100000cc0000000c1000006600000000000
00000000099944900007700000000121111000000dd00d900dd00dc000000000000000000aa00000000000000ccc100000cccc00000cc1000060060000000000
000000000944999000c7c700000000166100000000000dd000000dd00000000000000000a0000000000000000cc100000cccccc000ccc1000606006000000000
00000000044994400c1ccc00000000000000000090000000c0000000000000000000000000000000000000000c1000000111111000ccc1000600606000000000
0000000004444440c101100000000000000000009900d490c700d170000000000000000000000000000000000100000000000000000cc1000060060000000000
000000000044440010c100000000000000000000d4900d9dd1700dcd0000000000000000000000000000000000000000000000000000c1000006600000000000
00000000000000000c10000000000000000000000ddd00d00ddd00d0000000000000000000000000000000001000000000000000000000000000000000000000
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
00000d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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

