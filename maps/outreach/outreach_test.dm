/datum/map/outreach
	lobby_tracks = list(
		/decl/music_track/dirtyoldfrogg
	)

/datum/map_template/persistent/outreach
	name                 = "planet outreach"
	template_flags       = TEMPLATE_FLAG_SPAWN_GUARANTEED | TEMPLATE_FLAG_NO_RUINS
	modify_tag_vars      = FALSE
	template_categories  = list(MAP_TEMPLATE_CATEGORY_MAIN_SITE) //Templates must have a category, or they won't spawn
	tallness             = 4
	mappaths             = list(
		"maps/outreach/outreach-1.dmm",
		"maps/outreach/outreach-2.dmm",
		"maps/outreach/outreach-3.dmm",
		"maps/outreach/outreach-4.dmm"
	)

/datum/level_data/exoplanet/outreach
	name                = "outreach surface"
	level_id            = "outreach_surface"
	level_flags         = ZLEVEL_CONTACT | ZLEVEL_PLAYER | ZLEVEL_SEALED | ZLEVEL_SAVED
	ambient_light_level = 0.8
	base_area           = /area/exoplanet/outreach
	base_turf           = /turf/exterior/barren
	loop_turf_type      = /turf/exterior/mimic_edge/transition/loop
	border_filler       = /turf/unsimulated/dark_border
	exterior_atmosphere = list(
		/decl/material/gas/chlorine = MOLES_CELLSTANDARD,
		/decl/material/gas/nitrogen = MOLES_CELLSTANDARD,
	)

/datum/level_data/exoplanet/outreach/sky
	name                = "outreach sky"
	level_id            = "outreach_sky"
	base_area           = /area/exoplanet/outreach/sky
	base_turf           = /turf/exterior/open

/datum/level_data/exoplanet/outreach/mining
	name                = "outreach mines"
	level_id            = "outreach_mines"
	level_flags         = ZLEVEL_CONTACT | ZLEVEL_PLAYER | ZLEVEL_SEALED | ZLEVEL_SAVED | ZLEVEL_MINING
	base_area           = /area/exoplanet/outreach/mines/depth_1
	base_turf           = /turf/exterior/barren
	border_filler       = /turf/unsimulated/mineral

/datum/level_data/exoplanet/outreach/mining/bottom
	name                = "outreach mines bottom"
	level_id            = "outreach_mines_bottom"
	base_area           = /area/exoplanet/outreach/mines/depth_2

/obj/abstract/level_data_spawner/exoplanet/outreach
	name            = "outreach surface (level data spawner)"
	level_data_type = /datum/level_data/exoplanet/outreach

/obj/abstract/level_data_spawner/exoplanet/outreach/sky
	name            = "outreach sky (level data spawner)"
	level_data_type = /datum/level_data/exoplanet/outreach/sky

/obj/abstract/level_data_spawner/exoplanet/outreach/mining
	name            = "outreach mines (level data spawner)"
	level_data_type = /datum/level_data/exoplanet/outreach/mining

/obj/abstract/level_data_spawner/exoplanet/outreach/mining/bottom
	name            = "outreach mines bottom (level data spawner)"
	level_data_type = /datum/level_data/exoplanet/outreach/mining/bottom