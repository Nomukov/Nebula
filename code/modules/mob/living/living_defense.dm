/mob/living/proc/modify_damage_by_armor(def_zone, damage, damage_type, damage_flags, mob/living/victim, armor_pen, silent = FALSE)
	var/list/armors = get_armors_by_zone(def_zone, damage_type, damage_flags)
	. = args.Copy(2)
	for(var/armor in armors)
		var/datum/extension/armor/armor_datum = armor
		. = armor_datum.apply_damage_modifications(arglist(.))

/mob/living/get_blocked_ratio(def_zone, damage_type, damage_flags, armor_pen, damage)
	var/list/armors = get_armors_by_zone(def_zone, damage_type, damage_flags)
	. = 0
	for(var/armor in armors)
		var/datum/extension/armor/armor_datum = armor
		. = 1 - (1 - .) * (1 - armor_datum.get_blocked(damage_type, damage_flags, armor_pen, damage)) // multiply the amount we let through
	. = min(1, .)

/mob/living/proc/get_armors_by_zone(def_zone, damage_type, damage_flags)
	. = list()
	var/natural_armor = get_extension(src, /datum/extension/armor)
	if(natural_armor)
		. += natural_armor

/mob/living/bullet_act(var/obj/item/projectile/P, var/def_zone)

	//Being hit while using a deadman switch
	var/obj/item/assembly/signaler/signaler = get_active_hand()
	if(istype(signaler) && signaler.deadman)
		log_and_message_admins("has triggered a signaler deadman's switch")
		src.visible_message("<span class='warning'>[src] triggers their deadman's switch!</span>")
		signaler.signal()

	//Armor
	var/damage = P.damage
	var/flags = P.damage_flags()
	var/damaged
	if(!P.nodamage)
		damaged = apply_damage(damage, P.damage_type, def_zone, flags, P, P.armor_penetration)
		bullet_impact_visuals(P, def_zone, damaged)
	if(damaged || P.nodamage) // Run the block computation if we did damage or if we only use armor for effects (nodamage)
		. = get_blocked_ratio(def_zone, P.damage_type, flags, P.armor_penetration, P.damage)
	P.on_hit(src, ., def_zone)

// For visuals and blood splatters etc
/mob/living/proc/bullet_impact_visuals(var/obj/item/projectile/P, var/def_zone, var/damage)
	var/list/impact_sounds = LAZYACCESS(P.impact_sounds, get_bullet_impact_effect_type(def_zone))
	if(length(impact_sounds))
		playsound(src, pick(impact_sounds), 75)

/mob/living/get_bullet_impact_effect_type(var/def_zone)
	return BULLET_IMPACT_MEAT

/mob/living/proc/aura_check(var/type)
	if(!auras)
		return TRUE
	. = TRUE
	var/list/newargs = args - args[1]
	for(var/obj/aura/aura as anything in auras)
		var/result = 0
		switch(type)
			if(AURA_TYPE_WEAPON)
				result = aura.attackby(arglist(newargs))
			if(AURA_TYPE_BULLET)
				result = aura.bullet_act(arglist(newargs))
			if(AURA_TYPE_THROWN)
				result = aura.hitby(arglist(newargs))
			if(AURA_TYPE_LIFE)
				result = aura.life_tick()
		if(result & AURA_FALSE)
			. = FALSE
		if(result & AURA_CANCEL)
			break


//Handles the effects of "stun" weapons
/mob/living/proc/stun_effect_act(var/stun_amount, var/agony_amount, var/def_zone, var/used_weapon=null)
	flash_pain()

	if (stun_amount)
		SET_STATUS_MAX(src, STAT_STUN, stun_amount)
		SET_STATUS_MAX(src, STAT_WEAK, stun_amount)
		apply_effect(stun_amount, STUTTER)
		apply_effect(stun_amount, EYE_BLUR)

	if (agony_amount)
		apply_damage(agony_amount, PAIN, def_zone, used_weapon)
		apply_effect(agony_amount/10, STUTTER)
		apply_effect(agony_amount/10, EYE_BLUR)

/mob/living/proc/electrocute_act(var/shock_damage, var/obj/source, var/siemens_coeff = 1.0, def_zone = null)
	  return 0 //only carbon liveforms have this proc

/mob/living/emp_act(severity)
	var/list/L = src.get_contents()
	for(var/obj/O in L)
		O.emp_act(severity)
	..()

/mob/living/proc/resolve_item_attack(obj/item/I, mob/living/user, var/target_zone)
	return target_zone

//Called when the mob is hit with an item in combat. Returns the blocked result
/mob/living/proc/hit_with_weapon(obj/item/I, mob/living/user, var/effective_force, var/hit_zone)
	var/weapon_mention
	if(I.attack_message_name())
		weapon_mention = " with [I.attack_message_name()]"
	if(effective_force)
		visible_message("<span class='danger'>[src] has been [I.attack_verb.len? pick(I.attack_verb) : "attacked"][weapon_mention] by [user]!</span>")
	else
		visible_message("<span class='warning'>[src] has been [I.attack_verb.len? pick(I.attack_verb) : "attacked"][weapon_mention] by [user]!</span>")

	. = standard_weapon_hit_effects(I, user, effective_force, hit_zone)

	if(I.damtype == BRUTE && prob(33)) // Added blood for whacking non-humans too
		var/turf/simulated/location = get_turf(src)
		if(istype(location)) location.add_blood_floor(src)

//returns 0 if the effects failed to apply for some reason, 1 otherwise.
/mob/living/standard_weapon_hit_effects(obj/item/I, mob/living/user, var/effective_force, var/hit_zone)
	if(effective_force)
		return apply_damage(effective_force, I.damtype, hit_zone, I.damage_flags(), used_weapon=I, armor_pen=I.armor_penetration)

//this proc handles being hit by a thrown atom
/mob/living/hitby(var/atom/movable/AM, var/datum/thrownthing/TT)

	..()

	if(isliving(AM))
		var/mob/living/M = AM
		playsound(loc, 'sound/weapons/pierce.ogg', 25, 1, -1)
		if(skill_fail_prob(SKILL_COMBAT, 75))
			SET_STATUS_MAX(src, STAT_WEAK, rand(3,5))
		if(M.skill_fail_prob(SKILL_HAULING, 100))
			SET_STATUS_MAX(M, STAT_WEAK, rand(4,8))
		M.visible_message(SPAN_DANGER("\The [M] collides with \the [src]!"))

	if(!aura_check(AURA_TYPE_THROWN, AM, TT.speed))
		return

	if(istype(AM,/obj/))
		var/obj/O = AM
		var/dtype = O.damtype
		var/throw_damage = O.throwforce*(TT.speed/THROWFORCE_SPEED_DIVISOR)

		var/miss_chance = max(15*(TT.dist_travelled-2),0)

		if (prob(miss_chance))
			visible_message("<span class='notice'>\The [O] misses [src] narrowly!</span>")
			return

		src.visible_message("<span class='warning'>\The [src] has been hit by \the [O]</span>.")
		apply_damage(throw_damage, dtype, null, O.damage_flags(), O)

		if(TT.thrower)
			var/client/assailant = TT.thrower.client
			if(assailant)
				admin_attack_log(TT.thrower, src, "Threw \an [O] at the victim.", "Had \an [O] thrown at them.", "threw \an [O] at")

		if(O.can_embed() && (throw_damage > 5*O.w_class)) //Handles embedding for non-humans and simple_animals.
			embed(O)

	process_momentum(AM, TT)

/mob/living/momentum_power(var/atom/movable/AM, var/datum/thrownthing/TT)
	if(anchored || buckled)
		return 0

	. = (AM.get_mass()*TT.speed)/(get_mass()*min(AM.throw_speed,2))
	if(has_gravity() || check_space_footing())
		. *= 0.5

/mob/living/momentum_do(var/power, var/datum/thrownthing/TT, var/atom/movable/AM)
	if(power >= 0.75)		//snowflake to enable being pinned to walls
		var/direction = TT.init_dir
		throw_at(get_edge_target_turf(src, direction), min((TT.maxrange - TT.dist_travelled) * power, 10), throw_speed * min(power, 1.5), callback = CALLBACK(src,/mob/living/proc/pin_to_wall,AM,direction))
		visible_message(SPAN_DANGER("\The [src] staggers under the impact!"),SPAN_DANGER("You stagger under the impact!"))
		return

	. = ..()

/mob/living/proc/pin_to_wall(var/obj/O, var/direction)
	if(!istype(O) || O.loc != src || !O.can_embed())//Projectile is suitable for pinning.
		return

	var/turf/T = near_wall(direction,2)

	if(T)
		forceMove(T)
		visible_message(SPAN_DANGER("[src] is pinned to the wall by [O]!"),SPAN_DANGER("You are pinned to the wall by [O]!"))
		src.anchored = TRUE
		LAZYADD(pinned, O)
		if(!LAZYISIN(embedded,O))
			embed(O)

/mob/living/proc/embed(var/obj/O, var/def_zone=null, var/datum/wound/supplied_wound)
	O.forceMove(src)
	LAZYADD(embedded, O)
	src.verbs += /mob/proc/yank_out_object

//This is called when the mob is thrown into a dense turf
/mob/living/proc/turf_collision(var/turf/T, var/speed)
	visible_message("<span class='danger'>[src] slams into \the [T]!</span>")
	playsound(T, 'sound/effects/bangtaper.ogg', 50, 1, 1)//so it plays sounds on the turf instead, makes for awesome carps to hull collision and such
	apply_damage(speed*5, BRUTE)

/mob/living/proc/near_wall(var/direction,var/distance=1)
	var/turf/T = get_step(get_turf(src),direction)
	var/turf/last_turf = src.loc
	var/i = 1

	while(i>0 && i<=distance)
		if(!T || T.density) //Turf is a wall or map edge.
			return last_turf
		i++
		last_turf = T
		T = get_step(T,direction)

	return 0

// End BS12 momentum-transfer code.

/mob/living/attack_generic(var/mob/user, var/damage, var/attack_message)

	if(!damage || !istype(user))
		return

	adjustBruteLoss(damage)
	admin_attack_log(user, src, "Attacked", "Was attacked", "attacked")

	src.visible_message("<span class='danger'>\The [user] has [attack_message] \the [src]!</span>")
	user.do_attack_animation(src)
	spawn(1) updatehealth()
	return 1

/mob/living/proc/IgniteMob()
	if(fire_stacks > 0 && !on_fire)
		on_fire = 1
		set_light(4, l_color = COLOR_ORANGE)
		update_fire()

/mob/living/proc/ExtinguishMob()
	if(on_fire)
		on_fire = 0
		fire_stacks = 0
		set_light(0)
		update_fire()

/mob/living/proc/update_fire()
	return

/mob/living/proc/adjust_fire_stacks(add_fire_stacks) //Adjusting the amount of fire_stacks we have on person
	fire_stacks = clamp(fire_stacks + add_fire_stacks, FIRE_MIN_STACKS, FIRE_MAX_STACKS)

/mob/living/proc/handle_fire()
	if(fire_stacks < 0)
		fire_stacks = min(0, ++fire_stacks) //If we've doused ourselves in water to avoid fire, dry off slowly

	if(!on_fire)
		return 1
	else if(fire_stacks <= 0)
		ExtinguishMob() //Fire's been put out.
		return 1

	fire_stacks = max(0, fire_stacks - 0.2) //I guess the fire runs out of fuel eventually

	var/datum/gas_mixture/G = loc.return_air() // Check if we're standing in an oxygenless environment
	if(G.get_by_flag(XGM_GAS_OXIDIZER) < 1)
		ExtinguishMob() //If there's no oxygen in the tile we're on, put out the fire
		return 1

	var/turf/location = get_turf(src)
	location.hotspot_expose(fire_burn_temperature(), 50, 1)

/mob/living/fire_act(datum/gas_mixture/air, exposed_temperature, exposed_volume)
	//once our fire_burn_temperature has reached the temperature of the fire that's giving fire_stacks, stop adding them.
	//allow fire_stacks to go up to 4 for fires cooler than 700 K, since are being immersed in flame after all.
	if(fire_stacks <= 4 || fire_burn_temperature() < exposed_temperature)
		adjust_fire_stacks(2)
	IgniteMob()

/mob/living/proc/get_cold_protection()
	return 0

/mob/living/proc/get_heat_protection()
	return 0

//Finds the effective temperature that the mob is burning at.
/mob/living/proc/fire_burn_temperature()
	if (fire_stacks <= 0)
		return 0

	//Scale quadratically so that single digit numbers of fire stacks don't burn ridiculously hot.
	//lower limit of 700 K, same as matches and roughly the temperature of a cool flame.
	return max(2.25*round(FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE*(fire_stacks/FIRE_MAX_FIRESUIT_STACKS)**2), 700)

/mob/living/proc/reagent_permeability()
	return 1

/mob/living/lava_act(datum/gas_mixture/air, temperature, pressure)
	fire_act(air, temperature)
	FireBurn(0.4*vsc.fire_firelevel_multiplier, temperature, pressure)
	. =  (health <= 0) ? ..() : FALSE

// called when something steps onto a mob
// this handles mulebots and vehicles
/mob/living/Crossed(var/atom/movable/AM)
	AM.crossed_mob(src)
