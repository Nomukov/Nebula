#define STATE_ERROR          -1
#define STATE_MENU            0
#define STATE_SELF            1
#define STATE_CONTRACTS       2
#define STATE_OTHER           3

#define MAX_PENDING_CONTRACTS 5
/datum/computer_file/program/accounts
	filename = "accountman"
	filedesc = "Account management program"
	nanomodule_path = /datum/nano_module/program/accounts
	program_icon_state = "id"
	program_key_state = "id_key"
	program_menu_icon = "key"
	extended_desc = "Program for managing network accounts and group membership."
	size = 8
	category = PROG_COMMAND

/datum/nano_module/program/accounts
	name = "Account management program"
	var/prog_state = STATE_MENU
	var/datum/computer_file/data/account/selected_account
	var/selected_parent_group

	// The contract in the process of being created or modified.
	var/datum/network_contract/mod_contract
	// Showing the list of accounts able to be offered contracts.
	var/offering_contract

	// List of modifications pending on a contract.
	var/list/pending_modifications

/datum/nano_module/program/accounts/Destroy()
	selected_account = null
	if(mod_contract && !mod_contract.finalized)
		qdel(mod_contract)
	. = ..()

/datum/nano_module/program/accounts/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1, var/datum/topic_state/state = global.default_topic_state)
	var/list/data = host.initial_data()
	var/datum/computer_network/network = get_network()
	if(!network)
		data["error"] = "No accounts found. Check network connectivity."
		prog_state = STATE_ERROR
	switch(prog_state)
		if(STATE_SELF)
			data["account_name"] = selected_account.login
			data["account_password"] = selected_account.password
			data["account_fullname"] = selected_account.fullname
			data["account_groups"] = selected_account.groups

			data["routing_login"] = selected_account.routing_login ? selected_account.routing_login : "Routing disabled"
			data["routing_network"] = selected_account.routing_network ? selected_account.routing_network : ""
			data["routing_pin"] = selected_account.routing_pin ? "****" : ""
		if(STATE_CONTRACTS)
			data["account_fullname"] = selected_account.fullname
			if(!mod_contract)
				// Safety check
				if(offering_contract)
					offering_contract = FALSE
				data["auth_contracts"] = list()
				var/auth_index = 1
				for(var/datum/network_contract/contract in selected_account.get_authorized_contracts())
					var/list/active_instances = contract.get_instances()
					data["auth_contracts"] += list(list(
						"name" = contract.name,
						"title" = contract.job_title ? contract.job_title : "N/A",
						"hourly_pay" = contract.hourly_pay ? contract.format_value(contract.hourly_pay) : "N/A",
						"regular_pay" = contract.payment_amount ? contract.format_value(contract.payment_amount) : "N/A",
						"pay_period" = contract.get_readable_period(),
						"no_active" = length(active_instances),
						"auth_index" = auth_index
					))
					auth_index += 1

				data["held_contracts"] = list()
				var/held_index = 1
				for(var/datum/contract_instance/instance in selected_account.get_held_contracts())
					var/datum/network_contract/parent = instance.parent
					data["held_contracts"] += list(list(
						"name" = parent.name,
						"title" = parent.job_title ? parent.job_title : "N/A",
						"hourly_pay" = parent.hourly_pay ? parent.format_value(parent.hourly_pay) : "N/A",
						"regular_pay" = parent.payment_amount ? parent.format_value(parent.payment_amount) : "N/A",
						"next_pay" = instance.get_next_payment(TRUE),
						"held_index" = held_index
					))
					held_index += 1

				var/list/pending = selected_account.get_pending_contracts()
				if(length(pending))
					var/pending_index = 1
					data["pending_contracts"] = list()
					for(var/datum/network_contract/pending_contract in pending)
						data["pending_contracts"] += list(list(
							"name" = pending_contract.name,
							"pending_index" = pending_index
						))
						pending_index += 1
			else if(mod_contract.finalized && !(mod_contract in selected_account.get_authorized_contracts()))
				mod_contract = null
				offering_contract = FALSE
				data["error"] = "Authentication error. Please try again."
				prog_state = STATE_ERROR
			else
				// Safety check
				if(offering_contract && !mod_contract.finalized)
					offering_contract = FALSE

				data["contract_name"] = mod_contract.name ? mod_contract.name :  "Not set"
				data["contract_finalized"] = mod_contract.finalized

				if(offering_contract)
					data["offering"] = TRUE
					var/list/accounts = network.get_accounts()
					accounts -= mod_contract.owner
					accounts -= selected_account
					data["offering_list"] = list()
					for(var/datum/computer_file/data/account/A in accounts)
						data["offering_list"] += list(list(
							"account" = A.login,
							"fullname" = A.fullname
						))
				else
					// The contract grants a job title (and possibly hourly pay)
					if(!isnull(mod_contract.job_title))
						data["contract_title"] = mod_contract.job_title
						data["contract_hourly"] = mod_contract.hourly_pay ? mod_contract.format_value(mod_contract.hourly_pay) : "N/A"
						data["req_clockin"] = mod_contract.require_clockin
					if(!isnull(mod_contract.payment_period))
						data["contract_pay"] = mod_contract.payment_amount ? mod_contract.format_value(mod_contract.payment_amount) : "N/A"
						data["contract_period"] = mod_contract.get_readable_period()
						data["contract_reversed"] = mod_contract.reversed_payment ? "The holder of the contract pays the owner (YOU)" : "The owner of the contract (YOU) pays the holder"

					if(LAZYLEN(mod_contract.groups))
						data["contract_groups"] = mod_contract.groups.Copy()

					var/list/auth_contracts = mod_contract.get_authorized_contracts()
					if(LAZYLEN(auth_contracts))
						data["contract_auths"] = list()
						var/auth_index = 1
						for(var/datum/network_contract/contract in auth_contracts)
							data["contract_auths"] += list(list(
								"name" = contract.name,
								"auth_index" = auth_index
							))
							auth_index += 1

					if(!isnull(mod_contract.additional_clauses))
						data["contract_clauses"] = digitalPencode2html(mod_contract.additional_clauses)

					if(mod_contract.finalized)
						var/list/active_instances = mod_contract.get_instances()
						data["no_active"] = length(active_instances)
						var/active_index = 1
						for(var/datum/contract_instance/instance in active_instances)
							data["active_contracts"] += list(list(
								"holder" = instance.holder.login,
								"next_pay" = instance.get_next_payment(TRUE),
								"active_index" = active_index
							))
							active_index += 1

						if(LAZYLEN(pending_modifications))
							data["pending_modifications"] = list()
							var/mod_index = 1
							for(var/datum/contract_modification/mod in pending_modifications)
								data["pending_modifications"] += list(list(
									"name" = mod.name,
									"mod_index" = mod_index
								))
								mod_index += 1

						data["is_owner"] = (selected_account == mod_contract.owner)

		if(STATE_OTHER) // Modifying other accounts.
			var/datum/extension/network_device/acl/net_acl = network.access_controller
			if(!net_acl)
				data["error"] = "No access controller found on the network!"
				prog_state = STATE_ERROR
			else
				var/list/group_dict = net_acl.get_group_dict()
				if(!istype(selected_account))
					var/list/accounts = network.get_accounts()
					data["accounts"] = list()
					for(var/datum/computer_file/data/account/A in accounts)
						data["accounts"] += list(list(
							"account" = A.login,
							"fullname" = A.fullname
						))
				else
					data["account_name"] = selected_account.login
					data["account_fullname"] = selected_account.fullname
					if(!selected_parent_group)
						data["parent_groups"] = list()
						for(var/parent_group in group_dict)
							data["parent_groups"] += list(list(
										"name" = parent_group,
										"member" = (parent_group in selected_account.groups)
										))
					else
						var/list/child_groups = group_dict[selected_parent_group]
						if(!child_groups)
							data["error"] = "Invalid parent selected!"
							selected_parent_group = null
							return
						data["parent_group"] = selected_parent_group
						data["child_groups"] = list()
						for(var/child_group in child_groups)
							data["child_groups"] += list(list(
										"name" = child_group,
										"member" = (child_group in selected_account.groups)
									))
				data["sub_management"] = net_acl.allow_submanagement
	data["prog_state"] = prog_state
	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "account_management.tmpl", name, 900, 700, state = state)
		ui.auto_update_layout = 1
		ui.set_initial_data(data)
		ui.open()

/datum/computer_file/program/accounts/Topic(href, href_list, state)
	if(..())
		return 1

	var/mob/user = usr

	var/datum/computer_network/network = computer.get_network()
	var/datum/nano_module/program/accounts/module = NM
	if(!network)
		return
	switch(module.prog_state)
		if(STATE_MENU)
			if(href_list["self_mode"])
				var/datum/computer_file/data/account/A = computer.get_account()
				if(A)
					module.selected_account = A
					module.prog_state = STATE_SELF
					return TOPIC_REFRESH
				else
					to_chat(user, SPAN_WARNING("No account found. Please login through your system before reattempting."))
					return TOPIC_HANDLED

			if(href_list["contract_mode"])
				var/datum/computer_file/data/account/A = computer.get_account()
				if(A)
					module.selected_account = A
					module.prog_state = STATE_CONTRACTS
					return TOPIC_REFRESH
				else
					to_chat(user, SPAN_WARNING("No account found. Please login through your system before reattempting."))
					return TOPIC_HANDLED

			if(href_list["other_mode"])
				if(!computer.get_network_status(NET_FEATURE_RECORDS))
					to_chat(user, SPAN_WARNING("NETWORK ERROR - The network rejected access to account servers from your current connection."))
					return TOPIC_REFRESH
				module.selected_account = null // Reset selected account just in case.
				module.prog_state = STATE_OTHER
				return TOPIC_REFRESH

		if(STATE_SELF)
			if(!module.selected_account || computer.get_account() != module.selected_account)
				module.selected_account = null
				module.prog_state = STATE_MENU
				to_chat(user, SPAN_WARNING("Authentication error. Please relogin to your account."))
				return TOPIC_REFRESH

			if(href_list["change_password"])
				var/new_password = input(user, "Input new account password.", "Change Password", module.selected_account.password) as text|null
				var/password_check = alert(user, "Your new password will be [new_password]. Is this alright?", "Change Password", "Yes", "No")
				if(password_check == "Yes")
					if(!CanInteract(user,state))
						return TOPIC_HANDLED
					module.selected_account.password = new_password
					// Update the program's password too so the user doesn't have to login again.
					computer.password = new_password
					return TOPIC_REFRESH
				return TOPIC_HANDLED

			if(href_list["change_fullname"])
				var/new_fullname = input(user, "Input your full name.", "Change name", module.selected_account.fullname) as text|null
				if(!CanInteract(user,state))
					return TOPIC_HANDLED
				module.selected_account.fullname = new_fullname
				return TOPIC_REFRESH

			if(href_list["change_routing_login"])
				var/new_routing = input(user, "Input the login for the financial routing account. Leave blank to disable routing", "Change routing", module.selected_account.routing_login) as text|null
				new_routing = sanitize_for_account(new_routing)
				if(!CanInteract(user,state) || new_routing == module.selected_account.routing_login)
					return TOPIC_HANDLED
				if(!new_routing)
					module.selected_account.routing_login = null
				else
					module.selected_account.routing_login = new_routing

				module.selected_account.routing_network = null
				module.selected_account.routing_pin = null
				return TOPIC_REFRESH

			if(href_list["change_routing_network"])
				if(!module.selected_account.routing_login)
					return TOPIC_HANDLED
				var/new_network = input(user, "Input the network of the financial routing account.", "Change routing", module.selected_account.routing_network) as text|null
				new_network = sanitize(new_network)
				if(!CanInteract(user,state))
					return TOPIC_HANDLED

				module.selected_account.routing_network = new_network

			if(href_list["change_routing_pin"])
				if(!module.selected_account.routing_login)
					return TOPIC_HANDLED
				var/new_pin = input(user, "Input the pin of the financial routing account.", "Change routing", module.selected_account.routing_pin) as text|null
				new_pin = sanitize(new_pin)
				if(!CanInteract(user,state))
					return TOPIC_HANDLED

				module.selected_account.routing_pin = new_pin

		if(STATE_CONTRACTS)
			if(!module.selected_account || computer.get_account() != module.selected_account)
				module.selected_account = null
				if(module.mod_contract && !module.mod_contract.finalized)
					qdel(module.mod_contract)
					module.mod_contract = null
				to_chat(user, SPAN_WARNING("Authentication error. Please relogin to your account."))
				module.prog_state = STATE_MENU
				return TOPIC_REFRESH

			if(module.mod_contract)
				if(module.mod_contract.finalized && !(module.mod_contract in module.selected_account.get_authorized_contracts()))
					module.mod_contract = null
					return TOPIC_REFRESH
				// Redefined here for brevity
				var/datum/network_contract/mod_contract = module.mod_contract
				// Contract creation
				if(!mod_contract.finalized)
					if(href_list["set_name"])
						var/new_name = input(user, "Enter the name of the contract:", "Contract Name", mod_contract.name)
						new_name = sanitize(new_name)
						if(length(new_name) > 30)
							to_chat(user, SPAN_WARNING("The maximum length is 30 characters!"))
							return TOPIC_HANDLED

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state) || !length(new_name))
							return TOPIC_HANDLED

						mod_contract.name = new_name
						return TOPIC_REFRESH

					// Group handling
					if(href_list["add_group"])
						// We use only the accounts authorized groups, since we don't want ID access considered.
						var/list/valid_groups = module.selected_account.get_authorized_groups(network)
						if(!length(valid_groups))
							to_chat(user, SPAN_WARNING("You do not have authorization to grant membership in any groups."))
							return TOPIC_HANDLED

						if(LAZYLEN(mod_contract.groups))
							valid_groups -= mod_contract.groups

						var/added_group = input(user, "Select the group to add to the contract:", "Contract Groups") as anything in valid_groups

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state) || !added_group)
							return TOPIC_HANDLED

						LAZYADD(mod_contract.groups, added_group)
						return TOPIC_REFRESH

					if(href_list["remove_group"])
						var/group = href_list["remove_group"]
						if(LAZYISIN(mod_contract.groups, group))
							LAZYREMOVE(mod_contract.groups, group)
						return TOPIC_REFRESH

					// Contract Auth. handling
					if(href_list["add_auth"])
						var/list/owned_contracts = module.selected_account.owned_contracts
						if(!LAZYLEN(owned_contracts))
							to_chat(user, SPAN_WARNING("You are not the owner of any contracts!"))
							return TOPIC_REFRESH

						var/datum/network_contract/added_contract = input(user, "Select the contract to be authorized:", "Contract Authorization") as null|anything in owned_contracts

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state) || !added_contract || !LAZYISIN(owned_contracts, added_contract))
							return TOPIC_HANDLED

						mod_contract.add_auth_contract(added_contract)
						return TOPIC_REFRESH

					if(href_list["remove_auth"])
						var/contract_index = text2num(href_list["remove_auth"])

						var/list/auth_contracts = mod_contract.get_authorized_contracts()
						if(!isnum(contract_index) || contract_index == 0 || contract_index > LAZYLEN(auth_contracts))
							return TOPIC_HANDLED

						mod_contract.remove_auth_contract(auth_contracts[contract_index])
						return TOPIC_REFRESH

					// Job Handling
					if(href_list["set_job_title"])
						var/new_job_title = input(user, "Enter the job title granted by this contract:", "Job Title", mod_contract.job_title)
						new_job_title = sanitize(new_job_title)
						if(length(new_job_title) > 30)
							to_chat(user, SPAN_WARNING("The maximum length is 30 characters!"))
							return TOPIC_HANDLED

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state) || !length(new_job_title))
							return TOPIC_HANDLED

						mod_contract.job_title = new_job_title
						return TOPIC_REFRESH

					if(href_list["set_hourly_pay"])
						if(isnull(mod_contract.job_title))
							return TOPIC_HANDLED
						var/new_hourly_pay = input(user, "Enter the hourly pay for this job:", "Hourly Pay", mod_contract.hourly_pay) as num|null

						if(!isnum(new_hourly_pay) || new_hourly_pay < 0)
							to_chat(user, SPAN_WARNING("Invalid payment amount!"))
							return TOPIC_HANDLED
						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state))
							return TOPIC_HANDLED

						mod_contract.hourly_pay = new_hourly_pay
						return TOPIC_REFRESH

					if(href_list["toggle_clockin"])
						mod_contract.require_clockin = !mod_contract.require_clockin
						return TOPIC_HANDLED

					if(href_list["reset_job"])
						mod_contract.job_title = null
						mod_contract.hourly_pay = null

					// Regular Pay handling
					if(href_list["set_pay_period"])
						var/new_pay_period = alert(user, "Select the pay period for the contract:", "Pay Period", "Daily", "Weekly", "Biweekly")

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state))
							return TOPIC_HANDLED

						switch(new_pay_period)
							if("Daily")
								mod_contract.payment_period = 1 DAY
							if("Weekly")
								mod_contract.payment_period = 7 DAYS
							if("Biweekly")
								mod_contract.payment_period = 14 DAYS

						return TOPIC_REFRESH

					if(href_list["set_regular_pay"])
						if(isnull(mod_contract.payment_period))
							return TOPIC_HANDLED
						var/new_regular_pay = input(user, "Enter the regular pay for this contract:", "Regular Pay", mod_contract) as num|null

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state))
							return TOPIC_HANDLED

						mod_contract.payment_amount = new_regular_pay
						return TOPIC_REFRESH

					if(href_list["toggle_reverse_pay"])
						mod_contract.reversed_payment = !mod_contract.reversed_payment
						return TOPIC_REFRESH

					if(href_list["reset_regular_pay"])
						mod_contract.payment_period = null
						mod_contract.payment_amount = null
						mod_contract.reversed_payment = FALSE
						return TOPIC_REFRESH

					if(href_list["modify_additional_clauses"])
						var/new_clauses = sanitize(replacetext(input(usr, "Enter any additional clauses for the contract. You may use most tags from paper formatting. You may reference the owner and holder with \[owner\] and \[holder\] respectively.", "Add clauses", mod_contract.additional_clauses) as message|null, "\n", "\[br\]"), MAX_TEXTFILE_LENGTH)
						mod_contract.additional_clauses = new_clauses
						return TOPIC_REFRESH

					if(href_list["finalize_contract"])
						// Check to ensure the contract is valid
						var/list/errors = mod_contract.check_validity()
						if(length(errors))
							to_chat(user, SPAN_WARNING("Invalid contract! The following errors were found: [english_list(errors)]."))
							return TOPIC_HANDLED

						var/confirm = alert(user, "Are you sure you want to finalize this contract?", "Finalize Contract", "No", "Yes")

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user,state) || confirm != "Yes")
							return TOPIC_HANDLED
						mod_contract.finalize()
						to_chat(user, SPAN_NOTICE("Successfully finalized contract \'[mod_contract.name]\'!"))
						return TOPIC_REFRESH

				// Finalized contract operations.
				else
					// Modifying contract
					if(href_list["modify_contract"])
						// Only the owner of the contract may modify it.
						if(module.selected_account != mod_contract.owner)
							return TOPIC_REFRESH

						// TODO: Currently this displays datum types to the user.
						var/list/valid_mods = mod_contract.get_valid_modifications()

						var/list/mod_dict = list()

						for(var/mod_path in valid_mods)
							var/datum/contract_modification/mod_type = mod_path
							var/mod_name = initial(mod_type.name)
							mod_dict[mod_name] = mod_path

						if(!length(mod_dict))
							return TOPIC_HANDLED

						var/chosen_mod = input(user, "Select the modification type:", "Contract Modification") as null|anything in mod_dict
						if(!chosen_mod)
							return TOPIC_HANDLED

						var/chosen_mod_path = mod_dict[chosen_mod]
						var/datum/contract_modification/modification = new chosen_mod_path
						if(!istype(modification))
							return TOPIC_REFRESH

						if(modification.prompt_input(user, mod_contract, network))
							if(module.mod_contract != mod_contract || !module.selected_account)
								qdel(modification)
								return TOPIC_REFRESH

							if(!CanInteract(user, state))
								qdel(modification)
								return TOPIC_HANDLED

							LAZYADD(module.pending_modifications, modification)
						else
							qdel(modification)
						return TOPIC_REFRESH

					if(href_list["remove_modification"])
						var/modification_index = text2num(href_list["remove_modification"])
						if(!modification_index || LAZYLEN(module.pending_modifications) < modification_index)
							return TOPIC_REFRESH

						var/datum/contract_modification/mod = module.pending_modifications[modification_index]

						LAZYREMOVE(module.pending_modifications, mod)
						qdel(mod)
						return TOPIC_REFRESH

					if(href_list["preview_modifications"])
						if(!LAZYLEN(module.pending_modifications))
							return TOPIC_REFRESH
						var/preview = "The pending modifications are:"
						preview += "<br>"
						for(var/datum/contract_modification/mod in module.pending_modifications)
							preview += "* [mod.mod_message(mod_contract)]"
							preview += "<br>"
						to_chat(user, SPAN_NOTICE(preview))
						return TOPIC_HANDLED

					if(href_list["activate_modifications"])
						if(!LAZYLEN(module.pending_modifications))
							return TOPIC_REFRESH

						var/confirm = alert(user, "Are you sure you want to modify this contract? All contract holders will be notified.", "Contract modification", "No", "Yes")
						if(!CanInteract(user, state) || confirm != "Yes")
							return TOPIC_HANDLED

						var/list/valid_mods = mod_contract.get_valid_modifications()
						var/invalid_mod = FALSE
						for(var/datum/contract_modification/mod in module.pending_modifications)
							if(!(mod.type in valid_mods))
								invalid_mod = TRUE
								LAZYREMOVE(module.pending_modifications, mod)
								qdel(mod)

						if(invalid_mod)
							to_chat(user, SPAN_WARNING("Failed to modify contract. Invalid modifications detected!"))
							return TOPIC_REFRESH

						mod_contract.modify_contract(module.pending_modifications, network)
						to_chat(user, SPAN_NOTICE("Successfully modified contract!"))
						QDEL_NULL_LIST(module.pending_modifications)
						return TOPIC_REFRESH

					if(href_list["cancel_contract"])
						var/contract_index = text2num(href_list["cancel_contract"])
						if(!contract_index)
							return TOPIC_HANDLED
						var/list/contract_instances = mod_contract.get_instances()
						if(length(contract_instances) < contract_index)
							return TOPIC_REFRESH

						var/datum/contract_instance/instance = contract_instances[contract_index]
						var/confirm = alert(user, "Are you sure you want to cancel this contract, held by [instance.holder?.fullname]? All terms of the contract will immediately be rendered null.", "Contract cancellation", "No", "Yes")

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!CanInteract(user, state) || confirm != "Yes")
							return TOPIC_HANDLED

						instance.cancel_contract(FALSE)
						return TOPIC_REFRESH

					if(href_list["toggle_offer"])
						module.offering_contract = TRUE
						return TOPIC_REFRESH

					if(href_list["offer_contract"])
						var/account_login = href_list["offer_contract"]

						var/confirm = alert(user, "Are you sure you want to offer this contract to [account_login]?", "Contract Offer", "No", "Yes")

						if(module.mod_contract != mod_contract || !module.selected_account)
							return TOPIC_REFRESH

						if(!module.offering_contract || !CanInteract(user, state))
							return TOPIC_REFRESH

						if(confirm != "Yes")
							return TOPIC_HANDLED

						var/datum/computer_file/data/account/offeree = network.find_account_by_login(account_login)
						if(!istype(offeree))
							to_chat(user, SPAN_WARNING("Unable to offer contract to [account_login]! Please try again."))
							return TOPIC_REFRESH

						// Forbidden by UI.
						if(offeree == module.selected_account)
							to_chat(user, SPAN_WARNING("You cannot offer yourself a contract!"))
							return TOPIC_HANDLED
						// Ditto
						if(offeree == mod_contract.owner)
							to_chat(user, SPAN_WARNING("You cannot offer the owner its own contract!"))
							return TOPIC_HANDLED

						if((mod_contract in offeree.get_pending_contracts()) || (mod_contract in offeree.get_held_contract_parents()))
							to_chat(user, SPAN_WARNING("[account_login] has already been offered this contract!"))
							return TOPIC_HANDLED

						if(length(offeree.pending_contracts) >= MAX_PENDING_CONTRACTS)
							to_chat(user, SPAN_WARNING("[account_login] has too many pending contracts! Please try again later."))
							return TOPIC_HANDLED

						mod_contract.offer_contract(offeree, network, module.selected_account.fullname, network)
						module.offering_contract = FALSE
						to_chat(user, SPAN_NOTICE("Successfully offered contract!"))
						return TOPIC_REFRESH

				if(href_list["preview_contract"])
					var/formatted_contract = mod_contract.format_contract()
					show_browser(user, formatted_contract, "window=Contract Preview")
					return TOPIC_HANDLED

				if(href_list["delete_contract"])
					// Only the contract owner may delete the contract.
					if(module.selected_account != mod_contract.owner)
						return TOPIC_HANDLED

					var/confirm = alert(user, "Are you sure you want to delete this contract? All extant instances of this contract will be rendered void.", "Delete Contract", "No", "Yes")
					if(confirm != "Yes")
						return TOPIC_HANDLED

					if(LAZYLEN(mod_contract.instances))
						var/confirm2 = alert(user, "For security purposes, please confirm you want to delete this contract.", "Delete Contract", "No", "Yes")
						if(confirm2 != "Yes")
							return TOPIC_HANDLED

					if(module.mod_contract != mod_contract || !module.selected_account || mod_contract.owner != module.selected_account)
						return TOPIC_REFRESH

					if(!CanInteract(user,state))
						return TOPIC_HANDLED

					to_chat(user, SPAN_NOTICE("You successfully deleted the contract \'[mod_contract.name]\'"))
					QDEL_NULL(module.mod_contract)
					return TOPIC_REFRESH
			else
				if(href_list["select_contract"])
					var/auth_index = text2num(href_list["select_contract"])
					if(!auth_index)
						return TOPIC_REFRESH
					var/list/auth_contracts = module.selected_account.get_authorized_contracts()
					if(length(auth_contracts) >= auth_index)
						module.mod_contract = auth_contracts[auth_index]

					QDEL_NULL_LIST(module.pending_modifications)
					return TOPIC_REFRESH

				if(href_list["create_contract"])
					var/datum/network_contract/created_contract = new(module.selected_account)
					module.mod_contract = created_contract
					QDEL_NULL_LIST(module.pending_modifications)
					return TOPIC_REFRESH

				if(href_list["view_pending_contract"])
					var/pending_index = text2num(href_list["view_pending_contract"])
					if(!pending_index)
						return TOPIC_REFRESH

					var/list/pending_contracts = module.selected_account.get_pending_contracts()
					if(length(pending_contracts) >= pending_index)
						var/datum/network_contract/pending = pending_contracts[pending_index]
						var/formatted_contract = pending.format_contract(module.selected_account.fullname)
						show_browser(user, formatted_contract, "window=Contract")
					return TOPIC_HANDLED

				if(href_list["accept_pending_contract"])
					var/pending_index = text2num(href_list["accept_pending_contract"])
					if(!pending_index)
						return TOPIC_HANDLED

					if(LAZYLEN(module.selected_account.pending_contracts) < pending_index)
						return TOPIC_REFRESH

					var/list/pending_tuple = LAZYACCESS(module.selected_account.pending_contracts, pending_index)
					var/weakref/contract_ref = pending_tuple[1]
					var/datum/network_contract/offered = contract_ref.resolve()
					if(!istype(offered))
						LAZYREMOVE(module.selected_account.pending_contracts, list(pending_tuple))
						return TOPIC_REFRESH
					var/confirm = alert(user, "Are you sure you want to accept this contract, \'[offered.name]\'?", "Accept Contract Offer", "No", "Yes")
					if(!CanInteract(user, state) || confirm != "Yes")
						return TOPIC_REFRESH

					if(!module.selected_account || !LAZYISIN(module.selected_account.pending_contracts, pending_tuple))
						return TOPIC_REFRESH

					if(offered.accept_contract(module.selected_account, network, pending_tuple))
						to_chat(user, SPAN_NOTICE("Successfully accepted contract \'[offered.name]\'!"))
					else
						to_chat(user, SPAN_WARNING("Failed to accept contract! Please try again."))
					return TOPIC_REFRESH

				if(href_list["view_held_contract"])
					var/held_index = text2num(href_list["view_held_contract"])
					if(!isnum(held_index))
						return TOPIC_REFRESH
					var/list/held_contracts = module.selected_account.get_held_contracts()
					if(held_index != 0 && length(held_contracts) >= held_index)
						var/datum/contract_instance/instance = held_contracts[held_index]

						var/formatted_contract = instance.get_formatted_contract()
						if(!length(formatted_contract))
							to_chat(user, SPAN_WARNING("Unable to parse contract!"))
							return TOPIC_REFRESH
						show_browser(user, formatted_contract, "window=Contract")
						return TOPIC_HANDLED

					return TOPIC_REFRESH

				if(href_list["download_held_contract"])
					var/held_index = text2num(href_list["view_held_contract"])
					if(!isnum(held_index))
						return TOPIC_REFRESH
					var/list/held_contracts = module.selected_account.get_held_contracts()
					if(held_index != 0 && length(held_contracts) >= held_index)
						var/datum/contract_instance/instance = held_contracts[held_index]
						var/formatted_contract = instance.get_formatted_contract()
						if(!length(formatted_contract))
							to_chat(user, SPAN_WARNING("Unable to parse contract!"))
							return TOPIC_REFRESH
						var/browser_desc = "Save contract as:"
						var/datum/computer_file/data/text/contract_text = new()
						contract_text.stored_data = formatted_contract
						view_file_browser(user, "saving_contract", /datum/computer_file/data/text, OS_WRITE_ACCESS, browser_desc, contract_text)
					return TOPIC_REFRESH

				if(href_list["cancel_held_contract"])
					var/held_index = text2num(href_list["cancel_held_contract"])
					if(!held_index)
						return TOPIC_HANDLED
					var/list/held_contracts = module.selected_account.get_held_contracts()

					if(length(held_contracts) >= held_index)
						var/datum/contract_instance/instance = held_contracts[held_index]
						var/datum/network_contract/contract = instance.parent
						var/cancel_check = alert(user, "Are you sure you want to cancel this contract, \'[contract.name]\'? All terms of the contract will immediately be rendered null.", "Contract Cancellation", "No", "Yes")
						if(cancel_check == "Yes" && CanInteract(user,state))
							instance.cancel_contract()
							return TOPIC_REFRESH
						return TOPIC_HANDLED
		if(STATE_OTHER)
			if(!computer.get_network_status(NET_FEATURE_RECORDS))
				module.prog_state = STATE_MENU
				to_chat(user, SPAN_WARNING("NETWORK ERROR - The network rejected access to account servers from your current connection."))
				return TOPIC_REFRESH

			if(href_list["select_account"])
				var/account_login = href_list["select_account"]
				for(var/datum/computer_file/data/account/A in network.get_accounts())
					if(A.login == account_login)
						module.selected_account = A
						return TOPIC_REFRESH

			// Further actions require the ACL to be present on the network, so check if it exists first.
			var/datum/extension/network_device/acl/net_acl = network.access_controller
			if(!net_acl)
				module.selected_parent_group = null // Just in case.
				return TOPIC_REFRESH
			var/list/group_dict = net_acl.get_group_dict()

			if(href_list["create_account"])
				var/list/account_creation_access

				// Passing null access to create_account will ignore access checks on account servers, so only assign this
				// if the user doesn't have parent group account creation authorization.
				if(!net_acl.check_account_creation_auth(computer.get_account()))
					account_creation_access = NM.get_access(user)
				var/new_login = input(user, "Input new account login. Login will be sanitized.", "Account Creation") as text|null

				var/login_check = alert(user, "Account login will be [sanitize_for_account(new_login)]. Is this acceptable?","Account Creation", "Yes", "No")
				if(login_check == "Yes")
					var/new_password = input(user, "Input new account password.", "Account Creation") as text|null
					var/new_fullname = input(user, "Enter full name for account (e.g. John Smith)", "Account Creation") as text|null
					if(!CanInteract(user,state))
						return TOPIC_HANDLED
					if(network.create_account(null, new_login, new_password, new_fullname, account_creation_access, FALSE))
						to_chat(user, SPAN_NOTICE("Account successfully created!"))
						return TOPIC_REFRESH
					else
						to_chat(user, SPAN_WARNING("Account could not be created. It's possible an account with a matching login already exists, or you lack access to account servers."))
						return TOPIC_HANDLED
				else
					to_chat(user, SPAN_NOTICE("Account creation aborted."))
					return TOPIC_HANDLED

			if(href_list["recover_account"])
				var/list/account_recovery_access

				if(!net_acl.check_account_creation_auth(computer.get_account()))
					account_recovery_access = NM.get_access(user)

				var/list/backups = network.get_account_backups(account_recovery_access)
				if(!length(backups))
					to_chat(user, SPAN_WARNING("No account backups found on account servers!"))
					return TOPIC_HANDLED

				var/selected_login = input(user, "Select the account backup you would like to recover:", "Account Backups") as anything in backups
				if(!CanInteract(user, state) || !selected_login)
					return TOPIC_HANDLED

				if(network.find_account_by_login(selected_login))
					to_chat(user, SPAN_WARNING("An account with that login already exists on the network! Cannot recover backup."))
					return TOPIC_HANDLED

				var/datum/computer_file/data/account/backup = backups[selected_login]
				backup.backup = FALSE
				backup.filename = replacetext(backup.filename, backup.copy_string, null) // Remove the backup signifier on the file.
				to_chat(user, SPAN_NOTICE("Successfully recovered account [selected_login] from backup!"))
				return TOPIC_REFRESH

			if(href_list["mod_group"])
				if(!module.selected_account || QDELETED(module.selected_account))
					module.selected_parent_group = null
					return TOPIC_REFRESH
				var/group_name = href_list["mod_group"]
				var/is_parent_group = (group_name in group_dict)
				var/list/authorized_groups = get_authorized_groups(user)
				if(!is_parent_group && !LAZYISIN(group_dict[module.selected_parent_group], group_name)) // Safety check.
					module.selected_parent_group = null
					return TOPIC_REFRESH

				if(!(group_name in authorized_groups))
					to_chat(user, SPAN_WARNING("Access denied."))
					return TOPIC_HANDLED

				if(group_name in module.selected_account.groups)
					module.selected_account.groups -= group_name
				else
					module.selected_account.groups += group_name

				if(!is_parent_group)
					for(var/group in module.selected_account.groups)
						if(LAZYISIN(group_dict[module.selected_parent_group], group_name))
							module.selected_account.parent_groups |= module.selected_parent_group
							return TOPIC_REFRESH
					module.selected_account.parent_groups -= module.selected_parent_group

				return TOPIC_REFRESH

			if(href_list["select_parent_group"])
				if(module.selected_parent_group)
					return TOPIC_REFRESH
				var/parent_group = href_list["select_parent_group"]
				if(parent_group in group_dict)
					// In order to see child group membership, you need submanagement access or direct ACL access.
					if(!net_acl.has_access(module.get_access(user)))
						if(net_acl.allow_submanagement)
							var/list/child_access = list("[parent_group].[network.network_id]")
							if(!has_access(child_access, module.get_access(user)))
								to_chat(user, SPAN_WARNING("Access denied."))
								return TOPIC_HANDLED
						else
							to_chat(user, SPAN_WARNING("Access denied."))
							return TOPIC_HANDLED
					module.selected_parent_group = parent_group
					return TOPIC_REFRESH
				return TOPIC_HANDLED

	if(href_list["back"])
		switch(module.prog_state)
			if(STATE_ERROR)
				module.prog_state = STATE_MENU
			if(STATE_SELF)
				module.prog_state = STATE_MENU
				module.selected_account = null
			if(STATE_CONTRACTS)
				if(module.mod_contract)
					if(module.offering_contract)
						module.offering_contract = FALSE
					else
						if(!module.mod_contract.finalized)
							qdel(module.mod_contract)
						module.mod_contract = null
						QDEL_NULL_LIST(module.pending_modifications)
				else
					module.prog_state = STATE_MENU
			if(STATE_OTHER)
				if(module.selected_parent_group)
					module.selected_parent_group = null
				else if(module.selected_account)
					module.selected_account = null
				else
					module.prog_state = STATE_MENU
		return TOPIC_REFRESH
	SSnano.update_uis(module)
	return 1

// Returns the groups the user is allowed to grant/revoke.
/datum/computer_file/program/accounts/proc/get_authorized_groups(mob/user)
	. = list()
	var/datum/nano_module/program/accounts/module = NM
	var/datum/computer_network/network = computer.get_network()
	if(!network)
		return
	var/datum/extension/network_device/acl/net_acl = network.access_controller
	if(!net_acl)
		return

	if(net_acl.has_access(module.get_access(user)))
		return net_acl.get_all_groups()

	if(net_acl.allow_submanagement)
		var/datum/computer_file/data/account/current_account = computer.get_account()
		if(!current_account)
			return
		var/list/group_dict = net_acl.get_group_dict()
		for(var/parent_group in group_dict)
			var/list/child_groups = group_dict[parent_group]
			if(length(child_groups))
				if(parent_group in current_account.groups)
					. |= child_groups

#undef MAX_PENDING_CONTRACTS

#undef STATE_ERROR
#undef STATE_MENU
#undef STATE_SELF
#undef STATE_CONTRACTS
#undef STATE_OTHER