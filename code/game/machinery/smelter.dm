/obj/machinery/smelter
	name = "smelter"
	icon = 'icons/obj/machines/sorter.dmi'
	icon_state = "smelter"
	density = TRUE
	anchored = TRUE
	use_power = IDLE_POWER_USE
	idle_power_usage = 10
	active_power_usage = 2000

	circuit = /obj/item/circuitboard/smelter

	// base smelting speed - based on levels of manipulators
	var/speed = 10

	// based on levels of matter bins
	var/storage_capacity = 120

	var/list/stored_material = list()

	var/input_side = SOUTH
	var/output_side = null //by default it will be reversed input_side
	var/refuse_output_side = EAST

	var/progress = 0

	var/obj/current_item

	var/forbidden_materials = list(MATERIAL_CARDBOARD,MATERIAL_WOOD,MATERIAL_BIOMATTER)


/obj/machinery/smelter/Initialize()
	. = ..()
	if(!output_side)
		output_side = reverse_direction(input_side)


/obj/machinery/smelter/Destroy()
	if(current_item)
		current_item.forceMove(get_turf(src))
	eject_all_material()
	return ..()


/obj/machinery/smelter/update_icon()
	..()
	if(progress)
		icon_state = "smelter-process"
	else
		icon_state = "smelter"


/obj/machinery/smelter/Process()
	if(stat & BROKEN || stat & NOPOWER)
		progress = 0
		use_power(0)
		update_icon()
		return

	if(current_item)
		use_power(2)
		progress += speed
		progress += item_speed_bonus(current_item)
		if(progress >= 100)
			smelt()
			grab()
			use_power(1)
		update_icon()
	else
		grab()


/obj/machinery/smelter/proc/grab()
	for(var/obj/O in get_step(src, input_side))
		if(O.anchored)
			continue
		O.loc = src
		var/list/materials = result_materials(O)
		if(!materials?.len || !are_valid_materials(materials))
			eject(O, refuse_output_side)
			return
		current_item = O
		return


/obj/machinery/smelter/proc/smelt()
	smelt_item(current_item)
	current_item = null
	progress = 0
	eject_overflow()


/obj/machinery/smelter/proc/smelt_item(obj/smelting)
	var/list/materials = result_materials(smelting)

	if(materials)
		if(!are_valid_materials(materials))
			eject(smelting, refuse_output_side)
			return

		for(var/material in materials)
			if(!(material in stored_material))
				stored_material[material] = 0

			var/total_material = materials[material]

			if(istype(smelting,/obj/item/stack))
				var/obj/item/stack/material/S = smelting
				total_material *= S.get_amount()

			stored_material[material] += total_material

	for(var/obj/O in smelting.contents)
		smelt_item(O)

	qdel(smelting)


/obj/machinery/smelter/proc/are_valid_materials(list/materials)
	for(var/material in forbidden_materials)
		if(material in materials)
			return FALSE
	return TRUE


/obj/machinery/smelter/proc/result_materials(obj/O)
	if(istype(O, /obj/item/stack/ore))
		var/obj/item/stack/ore/ore = O
		var/ore/data = ore_data[ore.material]
		if(data.smelts_to)
			return list(data.smelts_to = 1)
		if(data.compresses_to)
			return list(data.compresses_to = 1)
	return O.get_matter()

// Some items are significantly easier to smelt
/obj/machinery/smelter/proc/item_speed_bonus(obj/smelting)
	if(istype(smelting, /obj/item/stack))
		return 30

	if(istype(smelting, /obj/item/stack/ore))
		return 20

	if(istype(smelting, /obj/item/material/shard))
		return 20

	// Just one material - makes smelting easier
	if(length(result_materials(smelting)) == 1)
		return 10

	return 0

/obj/machinery/smelter/proc/eject(obj/O, output_dir)
	O.loc = get_step(src, output_dir)


/obj/machinery/smelter/proc/eject_material_stack(material)
	var/obj/item/stack/material/stack_type = material_stack_type(material)

	// Sanity check: avoid an infinite loop in eject_all_material when trying to drop an invalid material
	if(!stack_type)
		stored_material[material] = 0
		CRASH("Attempted to drop an invalid material: [material]")

	var/ejected_amount = min(initial(stack_type.max_amount), round(stored_material[material]), storage_capacity)
	var/obj/item/stack/material/S = new stack_type(src, ejected_amount)
	eject(S, output_side)
	stored_material[material] -= ejected_amount


/obj/machinery/smelter/proc/eject_all_material(material = null)
	if(!material)
		for(var/mat in stored_material)
			eject_all_material(mat)
	while(stored_material[material] >= 1)
		eject_material_stack(material)


/obj/machinery/smelter/proc/eject_overflow()
	for(var/material in stored_material)
		while(stored_material[material] > storage_capacity)
			eject_material_stack(material)


/obj/machinery/smelter/RefreshParts()
	..()

	var/manipulator_rating = 0
	var/manipulator_count = 0
	for(var/obj/item/stock_parts/manipulator/M in component_parts)
		manipulator_rating += M.rating
		++manipulator_count
	for(var/obj/item/stock_parts/micro_laser/M in component_parts)
		manipulator_rating += M.rating
		++manipulator_count

	speed = initial(speed)*(manipulator_rating/manipulator_count)

	var/mb_rating = 0
	var/mb_count = 0
	for(var/obj/item/stock_parts/matter_bin/MB in component_parts)
		mb_rating += MB.rating
		++mb_count
	storage_capacity = round(initial(storage_capacity)*(mb_rating/mb_count))


/obj/machinery/smelter/attackby(var/obj/item/I, var/mob/user)
	if(default_deconstruction(I, user))
		return

	if(default_part_replacement(I, user))
		return

	..()


/obj/machinery/smelter/attack_hand(mob/user as mob)
	return nano_ui_interact(user)


/obj/machinery/smelter/ui_data()
	var/list/data = list()
	data["currentItem"] = current_item?.name
	data["progress"] = progress

	var/list/M = list()
	for(var/mtype in stored_material)
		if(stored_material[mtype] < 1)
			continue
		M.Add(list(list("name" = mtype, "count" = stored_material[mtype])))
	data["materials"] = M
	data["capacity"] = storage_capacity

	return data


/obj/machinery/smelter/nano_ui_interact(mob/user, ui_key = "main", datum/nanoui/ui = null, force_open = NANOUI_FOCUS)
	var/list/data = ui_data()

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "smelter.tmpl", src.name, 600, 400)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(1)


/obj/machinery/smelter/Topic(href, href_list)
	if (..()) return TRUE

	if(href_list["eject"])
		var/material = href_list["eject"]

		if(material in stored_material)
			eject_all_material(material)
		else
			eject_all_material()

	SSnano.update_uis(src)
	return FALSE
