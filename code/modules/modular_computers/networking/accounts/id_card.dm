#define CACHE_TIME 30 MINUTES
/obj/item/card/id/network
	name = "network identification card"
	desc = "A card used to provide ID and determine access. It connects remotely to a network to find its access codes."
	var/weakref/current_account
	color = COLOR_GRAY80
	detail_color = COLOR_SKY_BLUE

	var/list/cached_network_access = list()
	var/last_cached				  // The real time of day the network access was last cached

/obj/item/card/id/network/Initialize()
	set_extension(src, /datum/extension/network_device/id_card)
	return ..()

/obj/item/card/id/network/GetAccess(var/ignore_account)
	. = ..()
	var/datum/computer_file/data/account/access_account = resolve_account()
	var/datum/extension/network_device/D = get_extension(src, /datum/extension/network_device)
	var/datum/computer_network/network = D.get_network(NET_FEATURE_ACCESS)
	if(network)
		var/list/net_access = list()
		if(access_account && access_account.login != ignore_account)
			net_access = access_account.get_access(network)

		. += net_access
		cached_network_access = net_access
		last_cached = REALTIMEOFDAY
	else if(REALTIMEOFDAY <= (last_cached + CACHE_TIME))
		. += cached_network_access
	else if(length(cached_network_access))
		cached_network_access.Cut()
		visible_message(SPAN_SUBTLE("\The [src] beeps, indicating that it cleared its cached access."), range = 1)

/obj/item/card/id/network/proc/resolve_account(net_feature = NET_FEATURE_ACCESS, update_title = TRUE)
	if(!current_account)
		return
	var/datum/extension/network_device/D = get_extension(src, /datum/extension/network_device)
	var/datum/computer_network/network = D.get_network(net_feature)

	var/login = associated_network_account["login"]
	var/password = associated_network_account["password"]

	var/error
	var/datum/computer_file/data/account/check_account = current_account.resolve()
	if(!network) // No network or connectivity.
		error = "No network found"
	else if(!istype(check_account))
		error = "The specified account could not be found"
	else if(check_account.login != login || check_account.password != password) // The most likely case - login or password were changed.
		error = "Incorrect username or password"
	// Check if the account can be located on the network in case it was moved.
	else if(!(check_account in network.get_accounts()))
		error = "The specified account could not be found"

	if(error)
		current_account = null
		if(update_title)
			update_title()
		visible_message(SPAN_WARNING("\The [src] flashes an error: \'[error]!\'"), null, null,1)
	else
		return check_account

/obj/item/card/id/network/attack_self(mob/user)
	ui_interact(user)

/obj/item/card/id/network/ui_interact(mob/user, ui_key = "main",var/datum/nanoui/ui = null)
	var/data[0]
	var/login  = associated_network_account["login"]
	var/password = associated_network_account["password"]

	data["login"] = login ? login : "Enter Login"
	data["password"] = password ? stars(password, 0) : "Enter Password"

	var/datum/computer_file/data/account/logged_in = resolve_account()
	if(logged_in)
		data["logged_in"] = logged_in.login
		var/datum/contract_instance/clocked_in = logged_in.clocked_in?.resolve()
		if(istype(clocked_in))
			data["job_title"] = assignment

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data)
	if (!ui)
		ui = new(user, src, ui_key, "network_id.tmpl", "Network ID Settings", 540, 326)
		ui.set_initial_data(data)
		ui.open()

/obj/item/card/id/network/Topic(href, href_list, datum/topic_state/state)
	. = ..()
	if(.)
		return
	var/login  = associated_network_account["login"]
	var/password = associated_network_account["password"]
	if(href_list["change_login"])
		if(current_account)
			return TOPIC_REFRESH
		var/new_login = sanitize(input(usr, "Enter your account login:", "Account login", login) as text|null)
		if(new_login == login || !CanInteract(usr, DefaultTopicState()))
			return TOPIC_NOACTION
		associated_network_account["login"] = new_login

		current_account = null
		password = null
		return TOPIC_REFRESH

	if(href_list["change_password"])
		if(current_account)
			return TOPIC_REFRESH
		var/new_password = sanitize(input(usr, "Enter your account password:", "Account password") as text|null)
		if(new_password == password || !CanInteract(usr, DefaultTopicState()))
			return TOPIC_NOACTION
		associated_network_account["password"] = new_password

		current_account = null
		return TOPIC_REFRESH

	if(href_list["login_account"])
		if(current_account)
			return TOPIC_REFRESH
		if(login_account())
			to_chat(usr, SPAN_NOTICE("Account successfully logged in."))
		else
			to_chat(usr, SPAN_WARNING("Could not login to account. Check password or network connectivity."))
		return TOPIC_REFRESH

	if(href_list["clock_in"])
		var/datum/computer_file/data/account/logged_in = resolve_account()
		if(!logged_in)
			return TOPIC_REFRESH

		if(logged_in.clocked_in)
			return TOPIC_REFRESH

		var/list/job_titles = list()
		var/list/contract_dict = list()
		for(var/datum/contract_instance/instance in logged_in.get_held_contracts())
			if(instance.parent.job_title)
				var/title = "[instance.parent.job_title] ([instance.parent.name])"

				// In case of duplicate job titles
				while(title in job_titles)
					title = "[title]*"

				job_titles += title
				contract_dict[title] = instance

		if(!length(job_titles))
			to_chat(usr, SPAN_WARNING("You have no jobs available!"))
			return TOPIC_HANDLED

		var/job_title = input(usr, "Select the job to clock into:", "Clocking in") as null|anything in job_titles

		var/datum/contract_instance/clocked_in = contract_dict[job_title]

		if(!clocked_in || !(clocked_in in logged_in.get_held_contracts()))
			return TOPIC_REFRESH

		logged_in.clock_in(clocked_in)
		update_title()

		to_chat(usr, SPAN_NOTICE("You clock in as \a [assignment]."))
		return TOPIC_REFRESH

	if(href_list["clock_out"])
		if(clock_out())
			to_chat(usr, SPAN_NOTICE("You clock out."))
			update_title()
		return TOPIC_REFRESH

	if(href_list["log_out"])
		clock_out()
		current_account = null
		update_title()
		cached_network_access.Cut()
		return TOPIC_REFRESH

	if(href_list["settings"])
		var/datum/extension/network_device/D = get_extension(src, /datum/extension/network_device)
		D.ui_interact(usr)
		return TOPIC_HANDLED

/obj/item/card/id/network/proc/login_account()
	. = FALSE
	var/datum/extension/network_device/D = get_extension(src, /datum/extension/network_device)
	var/datum/computer_network/network = D.get_network(NET_FEATURE_ACCESS)
	if(!network)
		return
	var/login  = associated_network_account["login"]
	var/password = associated_network_account["password"]
	for(var/datum/computer_file/data/account/check_account in network.get_accounts())
		if(check_account.login == login && check_account.password == password)
			current_account = weakref(check_account)
			update_title()
			. = TRUE

	// Cache the access post login.
	GetAccess()

/obj/item/card/id/network/proc/clock_out()
	var/datum/computer_file/data/account/logged_in = resolve_account()
	if(!logged_in)
		return FALSE
	var/datum/contract_instance/clocked_in = logged_in.clocked_in?.resolve()
	if(istype(clocked_in))
		logged_in.clock_out()
		return TRUE

/obj/item/card/id/network/proc/get_network_id()
	var/datum/extension/network_device/D = get_extension(src, /datum/extension/network_device)
	var/datum/computer_network/network = D?.get_network()
	return network?.network_id

/obj/item/card/id/network/proc/update_clock_in(datum/contract_instance/instance, datum/computer_file/data/account/holder)
	if(resolve_account(NET_FEATURE_ACCESS) != holder)
		return FALSE

	var/mob/carrier = get_recursive_loc_of_type(/mob)

	// The contract instance handles the actual clocking out, in case there are multiple IDs with the holder account.
	if(!carrier || !carrier.client || carrier.client.is_afk())
		visible_message("\The [src] flashes a red light, indicating it clocked-out due to inactivity.")
		return FALSE

	return TRUE

// Updates the job title from the currently clocked in contract on the account.
/obj/item/card/id/network/proc/update_title()
	var/datum/computer_file/data/account/current = resolve_account(update_title = FALSE)
	if(!istype(current))
		assignment = null
		return

	assignment = current.get_active_job_title()

/obj/item/card/id/network/verb/flash_id()
	set name = "Flash ID"
	set category = "Object"
	set src in usr

	usr.visible_message("\The [usr] shows you: [html_icon(src)] [src.name]. The assignment on the card: '[src.assignment]'.",\
		"You flash your ID card: [html_icon(src)] [src.name]. The assignment on the card: '[src.assignment]'.")

	src.add_fingerprint(usr)

#undef CACHE_TIME