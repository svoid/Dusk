-- LICENSE
--
--   This software is dual-licensed to the public domain and under the following
--   license: you are granted a perpetual, irrevocable license to copy, modify,
--   publish, and distribute this file as you see fit.
--
-- VERSION 
--   0.1  (2016-06-01)  Initial release
--
-- AUTHOR
--   Forrest Smith
--
-- ADDITIONAL READING
--   https:--medium.com/@ForrestTheWoods/solving-ballistic-trajectories-b0165523348c
--
-- API
--    int solve_ballistic_arc(Vector3 proj_pos, float proj_speed, Vector3 target, float gravity, out Vector3 low, out Vector3 high);
--    int solve_ballistic_arc_moving(Vector3 proj_pos, float proj_speed, Vector3 target, Vector3 target_velocity, float gravity, out Vector3 s0, out Vector3 s1, out Vector3 s2, out Vector3 s3);
--    bool solve_ballistic_arc_lateral(Vector3 proj_pos, float lateral_speed, Vector3 target, float max_height, out float vertical_speed, out float gravity);
--    bool solve_ballistic_arc_lateral_moving(Vector3 proj_pos, float lateral_speed, Vector3 target, Vector3 target_velocity, float max_height_offset, out Vector3 fire_velocity, out float gravity, out Vector3 impact_point);
--
--    float ballistic_range(float speed, float gravity, float initial_height);
--
--    bool IsZero(double d);
--    int SolveQuadric(double c0, double c1, double c2, out double s0, out double s1);
--    int SolveCubic(double c0, double c1, double c2, double c3, out double s0, out double s1, out double s2);
--    int SolveQuartic(double c0, double c1, double c2, double c3, double c4, out double s0, out double s1, out double s2, out double s3);




-- SolveQuadric, SolveCubic, and SolveQuartic were ported from C as written for Graphics Gems I
-- Original Author: Jochen Schwarze (schwarze@isa.de)
-- https:--github.com/erich666/GraphicsGems/blob/240a34f2ad3fa577ef57be74920db6c4b00605e4/gems/Roots3And4.c

-- Utility function used by SolveQuadratic, SolveCubic, and SolveQuartic

local NAN = math.huge / math.huge

local function IsZero(d)
	local eps = 1e-9
	return d > -eps and d < eps
end

local function GetCubicRoot(value)
	if value > 0 then
		return math.pow(value, 1 / 3)
	elseif value < 0 then
		return -math.pow(-value, 1 / 3)
	else
		return 0
	end
end

-- Solve quadratic equation: c0*x^2 + c1*x + c2. 
-- Returns number of solutions.
local function SolveQuadric(c0, c1, c2)
	local s0 = NAN
	local s1 = NAN
	
	local p, q, D
	
	--/* normal form: x^2 + px + q = 0 */
	p = c1 / (2 * c0)
	q = c2 / c0
	
	D = p * p - q
	
	if IsZero(D) then
		s0 = -p
		return 1, s0, s1
	elseif D < 0 then
		return 0, s0, s1
	else -- /* if (D > 0) */
		local sqrt_D = math.sqrt(D)
		s0 = sqrt_D - p
		s1 = -sqrt_D - p
		return 2, s0, s1
	end
end

-- Solve cubic equation: c0*x^3 + c1*x^2 + c2*x + c3. 
-- Returns number of solutions.
local function SolveCubic(c0, c1, c2, c3)
	local s0, s1, s2
	
	local num
	local sub
	local A, B, C
	local sq_A, p, q
	local cb_p, D
	
	--/* normal form: x^3 + Ax^2 + Bx + C = 0 */
	A = c1 / c0
	B = c2 / c0
	C = c3 / c0
	
	--/*  substitute x = y - A/3 to eliminate quadric term:  x^3 +px + q = 0 */
	sq_A = A * A;
	p = 1 / 3 * (- 1 / 3 * sq_A + B)
	q = 1 / 2 * (2 / 27 * A * sq_A - 1 / 3 * A * B + C)
	
	--/* use Cardano's formula */
	cb_p = p * p * p
	D = q * q + cb_p
	
	if IsZero(D) then
		if IsZero(q) then -- /* one triple solution */ {
			s0 = 0
			num = 1
		else --/* one single and one double solution */ 
			local u = GetCubicRoot(-q)
			s0 = 2 * u
			s1 = - u
			num = 2
		end
	elseif D < 0 then -- /* Casus irreducibilis: three real solutions */
		local phi = 1 / 3 * math.acos(-q / math.sqrt(-cb_p))
		local t = 2 * math.sqrt(-p)
		
		s0 =   t * math.acos(phi)
		s1 = - t * math.acos(phi + math.pi / 3)
		s2 = - t * math.acos(phi - math.pi / 3)
		num = 3;
	else --/* one real solution */
		local sqrt_D = math.sqrt(D)
		local u = GetCubicRoot(sqrt_D - q)
		local v = -GetCubicRoot(sqrt_D + q)
		
		s0 = u + v
		num = 1
	end
	
	--/* resubstitute */
	sub = 1 / 3 * A
	
	if num > 0 then s0 -= sub end
	if num > 1 then s1 -= sub end
	if num > 2 then s2 -= sub end
	
	return num;
end

-- Solve quartic function: c0*x^4 + c1*x^3 + c2*x^2 + c3*x + c4. 
-- Returns number of solutions.
local function SolveQuartic(c0, c1, c2, c3, c4)
	local s0, s1, s2, s3
	s0 = NAN
	s1 = NAN
	s2 = NAN
	s3 = NAN
	
	local coeffs = {}
	local z, u, v, sub
	local A, B, C, D
	local sq_A, p, q, r
	local num
	
	--/* normal form: x^4 + Ax^3 + Bx^2 + Cx + D = 0 */
	A = c1 / c0
	B = c2 / c0
	C = c3 / c0
	D = c4 / c0
	
	--/*  substitute x = y - A/4 to eliminate cubic term: x^4 + px^2 + qx + r = 0 */
	sq_A = A * A
	p = - 3 / 8 * sq_A + B
	q = 1 / 8 * sq_A * A - 1 / 2 * A * B + C
	r = - 3 / 256 * sq_A * sq_A + 1 / 16 * sq_A * B - 1 / 4 * A * C + D
	
	if IsZero(r) then
		--/* no absolute term: y(y^3 + py + q) = 0 */
		
		coeffs[3] = q
		coeffs[2] = p
		coeffs[1] = 0
		coeffs[0] = 1
		
		num, s0, s1, s2 = SolveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3])
	else
		--/* solve the resolvent cubic ... */
		coeffs[3] = 1 / 2 * r * p - 1 / 8 * q * q
		coeffs[2] = -r
		coeffs[1] = -1 / 2 * p
		coeffs[0] = 1
		
		_, s0, s1, s2 = SolveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3])
		
		--/* ... and take the one real solution ... */
		z = s0;
		
		--/* ... to build two quadric equations */
		u = z * z - r;
		v = 2 * z - p;
		
		if (IsZero(u)) then
			u = 0;
		elseif (u > 0) then
			u = math.sqrt(u)
		else
			return 0, s0, s1, s2, s3
		end
		
		if IsZero(v) then
			v = 0
		elseif (v > 0) then
			v = math.sqrt(v)
		else
			return 0, s0, s1, s2, s3
		end
		
		coeffs[2] = z - u
		coeffs[1] = q < 0 and -v or v
		coeffs[0] = 1
		
		num, s0, s1 = SolveQuadric(coeffs[0], coeffs[1], coeffs[2])
		
		coeffs[2]= z + u
		coeffs[1] = q < 0 and v or -v
		coeffs[0] = 1
		
		local new = 0
		if num == 0 then
			new, s0, s1 = SolveQuadric(coeffs[0], coeffs[1], coeffs[2])
		elseif num == 1 then
			new, s1, s2 = SolveQuadric(coeffs[0], coeffs[1], coeffs[2])
		elseif num == 2 then
			new, s2, s3 = SolveQuadric(coeffs[0], coeffs[1], coeffs[2])
		end
		num += new
	end
	
	--/* resubstitute */
	sub = 1 / 4 * A
	
	if (num > 0) then s0 -= sub end
	if (num > 1) then s1 -= sub end
	if (num > 2) then s2 -= sub end
	if (num > 3) then s3 -= sub end
	
	return num, s0, s1, s2, s3
end


-- Calculate the maximum range that a ballistic projectile can be fired on given speed and gravity.
--
-- speed (float): projectile velocity
-- gravity (float): force of gravity, positive is down
-- initial_height (float): distance above flat terrain
--
-- return (float): maximum range
local function ballistic_range(speed, gravity, initial_height)
	
	-- Handling these cases is up to your project's coding standards
	assert(speed > 0 and gravity > 0 and initial_height >= 0, "ballistic_range called with invalid data")
	
	-- Derivation
	--   (1) x = speed * time * cos O
	--   (2) y = initial_height + (speed * time * sin O) - (.5 * gravity*time*time)
	--   (3) via quadratic: t = (speed*sin O)/gravity + sqrt(speed*speed*sin O + 2*gravity*initial_height)/gravity    [ignore smaller root]
	--   (4) solution: range = x = (speed*cos O)/gravity * sqrt(speed*speed*sin O + 2*gravity*initial_height)    [plug t back into x=speed*time*cos O]
	local angle = math.rad(45) -- no air resistence, so 45 degrees provides maximum range
	local cos = math.cos(angle)
	local sin = math.sin(angle)
	
	return (speed * cos / gravity) * (speed * sin + math.sqrt(speed * speed * sin * sin + 2 * gravity * initial_height))
end


-- Solve firing angles for a ballistic projectile with speed and gravity to hit a fixed position.
--
-- proj_pos (Vector3): point projectile will fire from
-- proj_speed (float): scalar speed of projectile
-- target (Vector3): point projectile is trying to hit
-- gravity (float): force of gravity, positive down
--
-- s0 (out Vector3): firing solution (low angle) 
-- s1 (out Vector3): firing solution (high angle)
--
-- return (int): number of unique solutions found: 0, 1, or 2.
local function solve_ballistic_arc(proj_pos, proj_speed, target, gravity)
	
	-- Handling these cases is up to your project's coding standards
	assert(proj_pos ~= target and proj_speed > 0 and gravity > 0, "solve_ballistic_arc called with invalid data")
	
	-- Initialize output parameters
	local s0 = Vector3.new()
	local s1 = Vector3.new()
	
	-- Derivation
	--   (1) x = v*t*cos O
	--   (2) y = v*t*sin O - .5*g*t^2
	-- 
	--   (3) t = x/(cos O*v)                                        [solve t from (1)]
	--   (4) y = v*x*sin O/(cos O * v) - .5*g*x^2/(cos^2 O*v^2)     [plug t into y=...]
	--   (5) y = x*tan O - g*x^2/(2*v^2*cos^2 O)                    [reduce; cos/sin = tan]
	--   (6) y = x*tan O - (g*x^2/(2*v^2))*(1+tan^2 O)              [reduce; 1+tan O = 1/cos^2 O]
	--   (7) 0 = ((-g*x^2)/(2*v^2))*tan^2 O + x*tan O - (g*x^2)/(2*v^2) - y    [re-arrange]
	--   Quadratic! a*p^2 + b*p + c where p = tan O
	--
	--   (8) let gxv = -g*x*x/(2*v*v)
	--   (9) p = (-x +- sqrt(x*x - 4gxv*(gxv - y)))/2*gxv           [quadratic formula]
	--   (10) p = (v^2 +- sqrt(v^4 - g(g*x^2 + 2*y*v^2)))/gx        [multiply top/bottom by -2*v*v/x; move 4*v^4/x^2 into root]
	--   (11) O = atan(p)
	
	local diff = target - proj_pos
	local diffXZ = Vector3.new(diff.x, 0, diff.z)
	local groundDist = diffXZ.magnitude
	
	local speed2 = proj_speed * proj_speed
	local speed4 = proj_speed * proj_speed * proj_speed * proj_speed
	local y = diff.y
	local x = groundDist
	local gx = gravity * x
	
	local root = speed4 - gravity * (gravity * x * x + 2 * y * speed2)
	
	-- No solution
	if root < 0 then
		return 0, s0, s1
	end
	
	root = math.sqrt(root)
	
	local lowAng = math.atan2(speed2 - root, gx)
	local highAng = math.atan2(speed2 + root, gx)
	local numSolutions = lowAng ~= highAng and 2 or 1
	
	local groundDir = diffXZ.Unit
	s0 = groundDir * math.cos(lowAng) * proj_speed + Vector3.yAxis * math.sin(lowAng) * proj_speed
	if numSolutions > 1 then
		s1 = groundDir * math.cos(highAng) * proj_speed + Vector3.yAxis * math.sin(highAng) * proj_speed
	end
	
	return numSolutions, s0, s1
end

-- Solve firing angles for a ballistic projectile with speed and gravity to hit a target moving with constant, linear velocity.
--
-- proj_pos (Vector3): point projectile will fire from
-- proj_speed (float): scalar speed of projectile
-- target (Vector3): point projectile is trying to hit
-- target_velocity (Vector3): velocity of target
-- gravity (float): force of gravity, positive down
--
-- s0 (out Vector3): firing solution (fastest time impact) 
-- s1 (out Vector3): firing solution (next impact)
-- s2 (out Vector3): firing solution (next impact)
-- s3 (out Vector3): firing solution (next impact)
--
-- return (int): number of unique solutions found: 0, 1, 2, 3, or 4.
local function solve_ballistic_arc_moving(proj_pos, proj_speed, target_pos, target_velocity, gravity)
	
	-- Initialize output parameters
	local s0 = Vector3.zero
	local s1 = Vector3.zero
	
	-- Derivation 
	--
	--  For full derivation see: blog.forrestthewoods.com
	--  Here is an abbreviated version.
	--
	--  Four equations, four unknowns (solution.x, solution.y, solution.z, time):
	--
	--  (1) proj_pos.x + solution.x*time = target_pos.x + target_vel.x*time
	--  (2) proj_pos.y + solution.y*time + .5*G*t = target_pos.y + target_vel.y*time
	--  (3) proj_pos.z + solution.z*time = target_pos.z + target_vel.z*time
	--  (4) proj_speed^2 = solution.x^2 + solution.y^2 + solution.z^2
	--
	--  (5) Solve for solution.x and solution.z in equations (1) and (3)
	--  (6) Square solution.x and solution.z from (5)
	--  (7) Solve solution.y^2 by plugging (6) into (4)
	--  (8) Solve solution.y by rearranging (2)
	--  (9) Square (8)
	--  (10) Set (8) = (7). All solution.xyz terms should be gone. Only time remains.
	--  (11) Rearrange 10. It will be of the form a*^4 + b*t^3 + c*t^2 + d*t * e. This is a quartic.
	--  (12) Solve the quartic using SolveQuartic.
	--  (13) If there are no positive, real roots there is no solution.
	--  (14) Each positive, real root is one valid solution
	--  (15) Plug each time value into (1) (2) and (3) to calculate solution.xyz
	--  (16) The end.
	
	local pposx = proj_pos.x
	local pposy = proj_pos.y
	local pposz = proj_pos.z
	local tposx = target_pos.x
	local tposy = target_pos.y
	local tposz = target_pos.z
	local tvelx = target_velocity.x
	local tvely = target_velocity.y
	local tvelz = target_velocity.z
	local pspeed = proj_speed
	
	local H = tposx - pposx
	local J = tposz - pposz
	local K = tposy - pposy
	local L = -.5 * gravity
	
	-- Quartic Coeffecients
	local c0 = L * L
	local c1 = -2 * tvely * L
	local c2 = tvely * tvely - 2 * K * L - pspeed * pspeed + tvelx * tvelx + tvelz * tvelz
	local c3 = 2 * K * tvely + 2 * H * tvelx + 2 * J * tvelz
	local c4 = K * K + H * H + J * J
	
	-- Solve quartic
	local times = {}
	local numTimes
	do
		local s0, s1, s2, s3
		numTimes, s0, s1, s2, s3 = SolveQuartic(c0, c1, c2, c3, c4)
		times[0] = s0
		times[1] = s1
		times[2] = s2
		times[3] = s3
	end
	
	-- Sort so faster collision is found first
	table.sort(times)
	
	-- Plug quartic solutions into base equations
	-- There should never be more than 2 positive, real roots.
	local solutions = {}
	local numSolutions = 0
	
	local i = 0
	while i < #times and numSolutions < 2 do
		local t = times[i]
		if t <= 0 or t ~= t then -- or NaN
			continue;
		end
		
		solutions[numSolutions].x = (H + tvelx * t) / t
		solutions[numSolutions].y = (K + tvely * t - L * t * t) / t
		solutions[numSolutions].z = (J + tvelz * t) / t
		numSolutions += 1
		i += 1
	end
	
	-- Write out solutions
	if (numSolutions > 0) then s0 = solutions[0] end
	if (numSolutions > 1) then s1 = solutions[1] end
	
	return numSolutions, s0, s1
end


-- Solve the firing arc with a fixed lateral speed. Vertical speed and gravity varies. 
-- This enables a visually pleasing arc.
--
-- proj_pos (Vector3): point projectile will fire from
-- lateral_speed (float): scalar speed of projectile along XZ plane
-- target_pos (Vector3): point projectile is trying to hit
-- max_height (float): height above Max(proj_pos, impact_pos) for projectile to peak at
--
-- fire_velocity (out Vector3): firing velocity
-- gravity (out float): gravity necessary to projectile to hit precisely max_height
--
-- return (bool): true if a valid solution was found
local function solve_ballistic_arc_lateral(proj_pos, lateral_speed, target_pos, max_height, fire_velocity, gravity)
	
	-- Handling these cases is up to your project's coding standards
	assert(proj_pos ~= target_pos and lateral_speed > 0 and max_height > proj_pos.y, "solve_ballistic_arc called with invalid data")
	
	fire_velocity = Vector3.zero
	gravity = NAN
	
	local diff = target_pos - proj_pos
	local diffXZ = Vector3.new(diff.x, 0, diff.z)
	local lateralDist = diffXZ.magnitude
	
	if lateralDist == 0 then
		return false
	end
	
	local time = lateralDist / lateral_speed
	
	fire_velocity = diffXZ.Unit * lateral_speed
	
	-- System of equations. Hit max_height at t=.5*time. Hit target at t=time.
	--
	-- peak = y0 + vertical_speed*halfTime + .5*gravity*halfTime^2
	-- end = y0 + vertical_speed*time + .5*gravity*time^s
	-- Wolfram Alpha: solve b = a + .5*v*t + .5*g*(.5*t)^2, c = a + vt + .5*g*t^2 for g, v
	local initial = proj_pos.y
	local peak = max_height
	local final = target_pos.y
	
	gravity = -4 * (initial - 2 * peak + final) / (time * time)
	fire_velocity.y = -(3 * initial - 4 * peak + final) / time
	
	return true
end

-- Solve the firing arc with a fixed lateral speed. Vertical speed and gravity varies. 
-- This enables a visually pleasing arc.
--
-- proj_pos (Vector3): point projectile will fire from
-- lateral_speed (float): scalar speed of projectile along XZ plane
-- target_pos (Vector3): point projectile is trying to hit
-- max_height (float): height above Max(proj_pos, impact_pos) for projectile to peak at
--
-- fire_velocity (out Vector3): firing velocity
-- gravity (out float): gravity necessary to projectile to hit precisely max_height
-- impact_point (out Vector3): point where moving target will be hit
--
-- return (bool): true if a valid solution was found
local function solve_ballistic_arc_lateral_moving(proj_pos, lateral_speed, target, target_velocity, max_height_offset)
	assert(proj_pos ~= target and lateral_speed > 0, "solve_ballistic_arc_lateral_moving called with invalid data")
	
	-- Initialize output variables
	local fire_velocity = Vector3.zero
	local gravity = 0
	local impact_point = Vector3.zero
	
	-- Ground plane terms
	local targetVelXZ = Vector3.new(target_velocity.x, 0, target_velocity.z)
	local diffXZ = target - proj_pos
	diffXZ.y = 0
	
	-- Derivation
	--   (1) Base formula: |P + V*t| = S*t
	--   (2) Substitute variables: |diffXZ + targetVelXZ*t| = S*t
	--   (3) Square both sides: Dot(diffXZ,diffXZ) + 2*Dot(diffXZ, targetVelXZ)*t + Dot(targetVelXZ, targetVelXZ)*t^2 = S^2 * t^2
	--   (4) Quadratic: (Dot(targetVelXZ,targetVelXZ) - S^2)t^2 + (2*Dot(diffXZ, targetVelXZ))*t + Dot(diffXZ, diffXZ) = 0
	local c0 = targetVelXZ:Dot(targetVelXZ) - lateral_speed * lateral_speed
	local c1 = 2 * diffXZ:Dot(targetVelXZ)
	local c2 = diffXZ:Dot(diffXZ)
	local n, t0, t1 = SolveQuadric(c0, c1, c2)
	
	-- pick smallest, positive time
	local valid0 = n > 0 and t0 > 0
	local valid1 = n > 1 and t1 > 0
	
	local t
	if not valid0 and not valid1 then
		return false, fire_velocity, gravity, impact_point
	elseif valid0 and valid1 then
		t = math.min(t0, t1)
	else
		t = valid0 and t0 or t1
	end
	
	-- Calculate impact point
	impact_point = target + (target_velocity * t)
	
	-- Calculate fire velocity along XZ plane
	local dir = impact_point - proj_pos
	fire_velocity = Vector3.new(dir.x, 0, dir.z).Unit * lateral_speed
	
	-- Solve system of equations. Hit max_height at t=.5*time. Hit target at t=time.
	--
	-- peak = y0 + vertical_speed*halfTime + .5*gravity*halfTime^2
	-- end = y0 + vertical_speed*time + .5*gravity*time^s
	-- Wolfram Alpha: solve b = a + .5*v*t + .5*g*(.5*t)^2, c = a + vt + .5*g*t^2 for g, v
	local initial = proj_pos.y
	local peak = math.max(proj_pos.y, impact_point.y) + max_height_offset
	local final = impact_point.y
	
	gravity = -4 * (initial - 2 * peak + final) / (t * t)
	fire_velocity.y = -(3 * initial - 4 * peak + final) / t
	
	return true, fire_velocity, gravity, impact_point
end


--[[
		External
--]]


function methods:GetRange(...)
	return ballistic_range(...)
end

function methods:GetArc(...)
	return solve_ballistic_arc(...)
end

function methods:GetArcMoving(...)
	return solve_ballistic_arc_moving(...)
end

function methods:GetLateralArc(...)
	return solve_ballistic_arc_lateral(...)
end

function methods:GetLateralArcMoving(...)
	return solve_ballistic_arc_lateral_moving(...)
end
