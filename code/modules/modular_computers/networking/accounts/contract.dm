#define MAX_NAME_LENGTH 50
// Each network contract datum represents a type of contract available to an account.
/datum/network_contract
	var/name

	var/list/groups		 // Group membership the holder is given.

	var/job_title		 // The position title granted by the contact while clocked in. Required if there is an hourly pay.
	var/hourly_pay		 // Pay given regularly while clocked in.
	var/require_clockin  // Whether or not group access requires clocking in.

	var/payment_period 	 // Time between payments. Can be used for salary, rent payments etc.
	var/payment_amount

	var/reversed_payment = FALSE // Whether or not payment goes from the owner to holder, or vice versa.

	var/datum/computer_file/data/account/owner

	VAR_PRIVATE/list/weakref/authorized_contracts // Contracts the contract holder is allowed to grant and revoke.

	var/list/datum/contract_instance/instances

	var/additional_clauses // Additional text clauses, optionally added to the contract.

	var/decl/currency/currency_type // TODO: Possibly add support for additional currencies.

	var/finalized = FALSE

/datum/network_contract/New(datum/computer_file/data/account/contract_owner)
	. = ..()
	if(contract_owner)
		owner = contract_owner
	if(!ispath(currency_type, /decl/currency))
		currency_type = global.using_map.default_currency

/datum/network_contract/Destroy(force)
	LAZYREMOVE(owner.owned_contracts, src)
	LAZYCLEARLIST(authorized_contracts)
	QDEL_NULL_LIST(instances)
	owner = null
	. = ..()

/datum/network_contract/proc/get_authorized_contracts()
	. = list()
	for(var/weakref/contract_ref in authorized_contracts)
		var/datum/network_contract/contract = contract_ref.resolve()
		if(!istype(contract) || !LAZYISIN(owner.owned_contracts, src))
			authorized_contracts -= contract_ref
			continue

		. |= authorized_contracts

/datum/network_contract/proc/get_authorized_contract_names()
	. = list()
	var/list/auth_contracts = get_authorized_contracts()
	if(length(auth_contracts))
		for(var/datum/network_contract/auth_contract in auth_contracts)
			. += auth_contract.name

/datum/network_contract/proc/get_instances()
	. = list()
	// Check for the validity of the contract instance.
	for(var/datum/contract_instance/instance in instances)
		if(!instance.holder || instance.parent != src)
			instances -= instance
			qdel(instance)
			continue

		. += instance

// Process periodic events on contract instances.
/datum/network_contract/proc/process_contracts(datum/computer_network/network)
	if(!LAZYLEN(instances) || !owner)
		return

	var/list/network_accounts = network.get_accounts_unsorted()

	for(var/datum/contract_instance/instance as anything in instances)
		if(!instance.holder || !(instance.holder in network_accounts))
			continue
		if(hourly_pay)
			process_hourly_pay(instance, network)

		if(payment_amount && payment_period)
			process_regular_pay(instance, network)


/datum/network_contract/proc/process_hourly_pay(datum/contract_instance/instance, datum/computer_network/network)
	var/current_time = SSmoney_accounts.get_current_time()

	// Unlikely to occur, but reset the hour count to the current time just in case.
	if(!instance.last_hour_count)
		instance.last_hour_count = current_time
		return

	if(!instance.check_clock_in(network))
		return

	var/time_delta = current_time - instance.last_hour_count
	if(time_delta > 0)
		instance.hour_counter += time_delta

	instance.last_hour_count = current_time

	var/hours_elapsed = FLOOR(instance.hour_counter / 1 HOUR)
	if(hours_elapsed >= 1)
		// Only one hourly payment is made at a time, but a debt may accumulate if a payment fails.
		var/error = attempt_payment(instance, network, hourly_pay, "Hourly payment for \'[job_title]\'")
		if(error)
			// Attempts to notify the user of the error.
			notify_holder(instance, network, error)
		else
			// Successfully made the payment, subtract one hour from the counter.
			notify_holder(instance, network, "Hourly payment processed for \'[job_title]\'!")
			instance.hour_counter -= 1 HOUR

/datum/network_contract/proc/process_regular_pay(datum/contract_instance/instance, datum/computer_network/network)
	// As above.
	var/current_time = SSmoney_accounts.get_current_time()
	if(!instance.last_pay)
		instance.last_pay = current_time
		return

	var/time_delta = current_time - instance.last_pay

	if(time_delta > payment_period)
		var/error = attempt_payment(instance, network, payment_amount, "Regular payment for \'[name]\'")

		if(error)
			var/datum/computer_file/data/email_message/payment_error = new()
			payment_error.title = "Payment failure for contract \'[name]\'"
			payment_error.stored_data = "A regular payment for the contract \'[name]\' between [owner.fullname] and [instance.holder.fullname] has failed for the following reason: [error]."

			network.receive_email(instance.holder, "financial_services@[network.network_id]", payment_error, FALSE)
			network.receive_email(owner, "financial_services@[network.network_id]", payment_error, FALSE)
		else
			// TODO: Consider letting failed payments accumulate, although this may be best dealt with between players on an individual basis.
			instance.last_pay = current_time

			var/datum/computer_file/data/email_message/payment_success = new()
			payment_success.title = "Payment for contract \'[name]\'"
			payment_success.stored_data = "A regular payment for the contract \'[name]\' between [owner.fullname] and [instance.holder.fullname] has been complete."

			network.receive_email(instance.holder, "financial_services@[network.network_id]", payment_success, FALSE)
			network.receive_email(owner, "financial_services@[network.network_id]", payment_success, FALSE)

// Returns null on success, error message on failure.
/datum/network_contract/proc/attempt_payment(datum/contract_instance/instance, datum/computer_network/network, amount, purpose)
	var/datum/money_account/owner_money = owner.get_financial_account(network)
	var/datum/money_account/instance_money = instance.holder.get_financial_account(network)

	if(!istype(owner_money))
		return "Unable to locate payroll account. Please contact your supervisor."
	if(!istype(instance_money))
		return "Unable to locate worker account. Please check with your financial provider or update your routing information."

	// Transfers can handle negative amounts, but this is more consistent.
	if(reversed_payment)
		return instance_money.transfer(owner_money, amount, purpose)

	return owner_money.transfer(instance_money, amount, purpose)

/datum/network_contract/proc/offer_contract(datum/computer_file/data/account/offeree, datum/computer_network/network, offering_name)
	if(!finalized)
		log_error("Attempted to offer non-finalized contract!")
		return

	if(offeree == owner)
		return

	// Only one contract of a type per holder.
	var/list/instances = get_instances()
	for(var/datum/contract_instance/instance in instances)
		if(instance.holder == offeree)
			return

	if(!istype(network))
		return

	var/datum/computer_file/data/email_message/offer = new()
	offer.title = "New contract offer \'[name]\'"
	offer.stored_data = "You have receieved a new contract offer (\'[name]\') from [owner.fullname]. Please see the account management program for details."

	network.receive_email(offeree, "contract_services@[network.network_id]", offer, FALSE)

	LAZYADD(offeree.pending_contracts, list(list(weakref(src), offering_name)))

/datum/network_contract/proc/accept_contract(datum/computer_file/data/account/offeree, datum/computer_network/network, list/pending_tuple)
	LAZYREMOVE(offeree.pending_contracts, list(pending_tuple))

	if(src in offeree.get_held_contract_parents())
		return FALSE

	var/datum/computer_file/data/email_message/acceptance = new()
	acceptance.title = "Contract Acceptance \'[name]\'"
	acceptance.stored_data = "[offeree.fullname] hass accepted the contract \'[name]\' from [pending_tuple[2]]. Please see the account management program for details."

	network.receive_email(owner, "contract_services@[network.network_id]", acceptance, FALSE)

	var/datum/contract_instance/instance = new(src, offeree, pending_tuple[2])
	LAZYADD(instances, instance)
	LAZYADD(offeree.held_contracts, instance)
	return TRUE

// Modifies the contract from a list of contract modifications. Sends e-mails to all current holders.
/datum/network_contract/proc/modify_contract(list/pending_modifications, datum/computer_network/network)
	if(!LAZYLEN(pending_modifications) || !istype(network))
		return FALSE

	var/datum/computer_file/data/email_message/alert_message = new()
	alert_message.title = "Alert: Modifications made to contract \'[name]\'"
	alert_message.stored_data = "Modifications have been made to a contract you are party to. The modifications are as follows: <br>"

	for(var/datum/contract_modification/mod in pending_modifications)
		alert_message.stored_data += "* [mod.mod_message(src)]"
		alert_message.stored_data += "<br>"

		mod.execute(src, network)

	network.receive_email(owner, "contract_services@[network.network_id]", alert_message, FALSE)

	for(var/datum/contract_instance/instance in get_instances())
		var/datum/computer_file/data/account/holder = instance.holder
		if(istype(holder))
			network.receive_email(holder, "contract_services@[network.network_id]", alert_message, FALSE)

	return TRUE

// Notifies the contract instance holder of a message via active network IDs.
/datum/network_contract/proc/notify_holder(datum/contract_instance/instance, datum/computer_network/network, message)
	var/datum/computer_file/data/account/holder = instance.holder
	var/list/network_ids = network.get_devices_by_type(/obj/item/card/id/network)

	// Find all IDs with the account logged in.
	for(var/obj/item/card/id/network/id in network_ids)
		if(id.current_account == weakref(holder))
			id.visible_message(SPAN_NOTICE("\The [id] flashes a message: \"[message]\""))

// Returns an empty list if the contract is valid. Returns a list of error strings if not.
/datum/network_contract/proc/check_validity()
	. = list()
	if(!length(name))
		. += "The contract must have a name"

	// This should technically be impossible due to how contract creation is done.
	if(!length(job_title) && hourly_pay)
		. += "The contract must have a job title"

	// Ditto
	if(!payment_period && payment_amount)
		. += "The contract must have a pay period"

	if(payment_period && !payment_amount)
		. += "The contract must have a regular payment set"

/datum/network_contract/proc/finalize()
	if(!owner)
		return

	finalized = TRUE
	LAZYADD(owner.owned_contracts, src)

/datum/network_contract/proc/get_valid_modifications()
	. = list()
	. += /datum/contract_modification/name

	. += /datum/contract_modification/add_auth
	. += /datum/contract_modification/remove_auth

	. += /datum/contract_modification/add_group
	. += /datum/contract_modification/remove_group

	if(job_title)
		. += /datum/contract_modification/job_title
		. += /datum/contract_modification/hourly_pay

	if(payment_period && !reversed_payment)
		. += /datum/contract_modification/regular_pay

// Returns the contract formatted into HTML.
/datum/network_contract/proc/format_contract(holder_fullname, datum/computer_network/network)
	if(!owner)
		return

	if(!holder_fullname)
		holder_fullname = "HOLDER NAME"

	var/decl/currency/display_currency = GET_DECL(currency_type)

	. = "<html><head><title>TERMS OF AGREEMENT: [name]</title></head>"
	. += "<body><center><h2>Terms of Agreement \'[name]\' between [owner.fullname] and [holder_fullname]</h2></center>"

	if(job_title)
		. += "<p> [holder_fullname] shall be entitled to the use of the title \'[job_title]\' during active employment. "
		if(hourly_pay)
			. += "During this time, they are entitled to an hourly pay of [display_currency.format_value(hourly_pay)]."
		. += "</p>"

	if(payment_amount && payment_period)
		if(reversed_payment)
			. += "<p>While the contract is in force, [holder_fullname] shall pay [owner.fullname] [display_currency.format_value(payment_amount)] every [get_readable_period()]."
		else
			. += "<p>While the contract is in force, [owner.fullname] shall pay [holder_fullname] [display_currency.format_value(payment_amount)] every [get_readable_period()]."
		. += "</p>"

	if(length(groups))
		. += "<p>Under the terms of this agreement, [holder_fullname] has been granted membership in the following network groups: [english_list(groups)]."
		if(require_clockin)
			. += " Membership in these groups is only granted while [holder_fullname] is clocked in as an employee."

		. += "</p>"

	var/list/auth_names = get_authorized_contract_names()
	if(length(auth_names))
		. += "<p>Under the terms of this agreement, [holder_fullname] has been granted authorization to issue the following contracts on behalf of [owner.fullname]: [english_list(auth_names)].</p>"

	if(length(additional_clauses))
		var/formatted_clauses = contractpencode2html(additional_clauses, holder_fullname)
		. += "<p>[formatted_clauses]</p>"

	. += "<p>Any breach of these terms will notify all parties via e-mail. Cancellation of these terms may occur at any time by either party. Failure to adhere to these terms may incur civil or criminal penalties according to local statutes."
	. += " Modification of these terms may occur at the behest of [owner.fullname]. No terms may be modified which would incur payments from [holder_fullname] greater than the terms of the original agreement. All parties shall be notified in the event that these changes occur.</p>"

	. += "<p><i><small>Contract terms enforced by encrypTract (R) Network Services. encrypTract (R) is not responsible for financial loss incurred by the breakage of these terms.</small></i></p>"

	. += "</body></html>"

/datum/network_contract/proc/contractpencode2html(text, holder_fullname)
	if(owner)
		text = replacetext(text, "\[owner\]", owner.fullname)

	if(holder_fullname)
		text = replacetext(text, "\[holder\]", holder_fullname)

	return digitalPencode2html(text)

// Helper to format amounts into the contract currency
/datum/network_contract/proc/format_value(amt)
	if(!ispath(currency_type, /decl/currency))
		currency_type = global.using_map.default_currency
	var/decl/currency/currency_decl = GET_DECL(currency_type)

	return currency_decl.format_value(amt)

// This is implemented generically, but the only options available to players are daily, weekly, and biweekly.
/datum/network_contract/proc/get_readable_period()
	if(!payment_period)
		return "N/A"
	return minutes_to_readable(FLOOR(payment_period / (1 MINUTE)))

/datum/network_contract/proc/add_auth_contract(datum/network_contract/contract)
	LAZYDISTINCTADD(authorized_contracts, weakref(contract))

/datum/network_contract/proc/remove_auth_contract(datum/network_contract/contract)
	LAZYREMOVE(authorized_contracts, weakref(contract))

/datum/network_contract/proc/get_granted_groups(var/datum/computer_network/network)
	if(!owner || !network)
		return

	var/list/authorized_groups = owner.get_authorized_groups(network)
	// Only grant groups that the owner is still able to grant.
	return groups & authorized_groups

/datum/contract_instance
	var/name
	var/datum/network_contract/parent
	var/datum/computer_file/data/account/holder

	var/authorizer // The login of who authorized this contract.

	// world.realtime of the last pay period, if it exists.
	var/last_pay

	// world.realtime of the last time hour_counter was incremented.
	var/last_hour_count
	var/hour_counter

/datum/contract_instance/New(datum/network_contract/parent_contract, datum/computer_file/data/account/holder_account, contract_authorizer)
	. = ..()
	if(parent_contract)
		parent = parent_contract
		name = parent_contract.name
	if(holder_account)
		holder = holder_account
	if(contract_authorizer)
		authorizer = contract_authorizer

	last_pay = SSmoney_accounts.get_current_time()

/datum/contract_instance/Destroy(force)
	send_cancellation_email()
	if(holder)
		holder.clock_out(src)

		LAZYREMOVE(holder.held_contracts, src)

	if(parent)
		if(LAZYISIN(parent.instances, src))
			parent.instances -= src

	holder = null
	parent = null

	. = ..()

/datum/contract_instance/proc/clock_in()
	last_hour_count = SSmoney_accounts.get_current_time()

/datum/contract_instance/proc/clock_out()
	if(last_hour_count)
		var/time_delta = SSmoney_accounts.get_current_time() - last_hour_count
		hour_counter += time_delta

	last_hour_count = null

/datum/contract_instance/proc/get_next_payment(short = FALSE)
	if(!parent.payment_amount || !parent.payment_period)
		return short ? "N/A" : "No payments are currently scheduled."

	var/next_pay = last_pay + parent.payment_period
	var/next_pay_text = next_pay > 0 ? time2text(next_pay, "MMM DD hh:mm") : "A payment is scheduled shortly."

	if(short)
		return next_pay_text

	if(parent.reversed_payment)
		return "A payment of [parent.format_value(parent.payment_amount)]to [parent.owner.fullname] is scheduled at [next_pay_text]."

	return "A payment of [parent.format_value(parent.payment_amount)]to [holder.fullname] is scheduled at [next_pay_text]."

// Checks if the contract is actively clocked in. Requires an ID on an active player
/datum/contract_instance/proc/check_clock_in(datum/computer_network/network)
	if(!holder || !holder.clocked_in || holder.clocked_in.resolve() != src)
		return FALSE

	var/list/network_ids = network.get_devices_by_type(/obj/item/card/id/network)

	// Find all IDs with the account logged in.
	for(var/obj/item/card/id/network/id in network_ids)
		if(id.current_account == weakref(holder))
			. = max(., id.update_clock_in(src, holder))

	// Failed to find an active ID. Clock out the holder account
	if(!.)
		holder.clock_out()

// Returns the contract in readable format
/datum/contract_instance/proc/get_formatted_contract()
	if(!parent || !holder)
		return

	return parent.format_contract(holder.fullname)

/datum/contract_instance/proc/send_cancellation_email(notify_parent = TRUE)
	if(!parent?.owner && !holder)
		return

	var/datum/computer_file/data/email_message/cancellation = new()
	cancellation.title = "Contract \'[name]\' cancellation"
	cancellation.source = "encrypTract@PLEXMAIL"
	if(parent && parent.owner)
		cancellation.stored_data = "The contract \'[name]\' between [parent.owner.fullname] and [holder.fullname] has been cancelled. All further financial transactions have been cancelled."
	else
		cancellation.stored_data = "The contract \'[name]\' has been cancelled. All further financial transactions have been cancelled."

	var/hours_owed = FLOOR(hour_counter / 1 HOUR)
	if(hours_owed)
		cancellation.stored_data += " At the time of contract cancellation, [hours_owed]\s hours of wages were owed."

	cancellation.set_timestamp()

	if(parent && parent.owner)
		parent.owner?.receive_mail(cancellation.Clone())

	holder?.receive_mail(cancellation.Clone())

// Cancels the contract, notifying the parent and holder.
/datum/contract_instance/proc/cancel_contract(notify_parent = TRUE)
	send_cancellation_email(notify_parent)
	if(parent)
		if(LAZYISIN(parent.instances, src))
			parent.instances -= src

	if(holder)
		holder.clock_out(src)
		LAZYREMOVE(holder.held_contracts, src)

	parent = null
	holder = null

	qdel_self()

/datum/contract_modification
	var/name

// Return FALSE on failure, requesting deletion. Return TRUE on success.
/datum/contract_modification/proc/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)

// Returns the modification message sent to holders of the contract.
/datum/contract_modification/proc/mod_message(datum/network_contract/parent)

/datum/contract_modification/proc/execute(datum/network_contract/parent, datum/computer_network/network)

/datum/contract_modification/name
	name = "Change Name"

	var/new_name

/datum/contract_modification/name/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	new_name = input(user, "Enter the new name of the contract:", "Contract Name", parent.name)
	new_name = sanitize(new_name)
	if(length(new_name) > MAX_NAME_LENGTH)
		to_chat(user, SPAN_WARNING("The maximum length is [MAX_NAME_LENGTH] characters!"))
		new_name = null
		return FALSE

	if(!length(new_name))
		return FALSE

	return TRUE

/datum/contract_modification/name/mod_message(datum/network_contract/parent)
	return "The name of the contract has been changed to \'[new_name]\'"

/datum/contract_modification/name/execute(datum/network_contract/parent, datum/computer_network/network)
	parent.name = new_name

/datum/contract_modification/job_title
	name = "Change Job Title"

	var/new_job_title

/datum/contract_modification/job_title/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	new_job_title = input(user, "Enter the new job title:", "Contract Job Title", parent.job_title)
	new_job_title = sanitize(new_job_title)
	if(length(new_job_title) > MAX_NAME_LENGTH)
		to_chat(user, SPAN_WARNING("The maximum length is [MAX_NAME_LENGTH] characters!"))
		new_job_title = null
		return FALSE

	if(!length(new_job_title))
		return FALSE

	return TRUE

/datum/contract_modification/job_title/mod_message(datum/network_contract/parent)
	return "The job title granted by the contract has been changed to \'[new_job_title]\'"

/datum/contract_modification/job_title/execute(datum/network_contract/parent, datum/computer_network/network)
	parent.job_title = new_job_title

/datum/contract_modification/hourly_pay
	name = "Change Hourly Pay"

	var/new_hourly_pay

/datum/contract_modification/hourly_pay/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	new_hourly_pay = input(user, "Enter the new hourly pay for this job:", "Hourly Pay", parent.hourly_pay) as num|null
	if(!isnum(new_hourly_pay) || new_hourly_pay < 0)
		to_chat(user, SPAN_WARNING("Invalid payment amount!"))
		new_hourly_pay = null
		return FALSE

	return TRUE

/datum/contract_modification/hourly_pay/mod_message(datum/network_contract/parent)
	return "The hourly pay of the contract has been changed to [parent.format_value(new_hourly_pay)]"

/datum/contract_modification/hourly_pay/execute(datum/network_contract/parent, datum/computer_network/network)
	parent.hourly_pay = new_hourly_pay

/datum/contract_modification/regular_pay
	name = "Change Regular Pay"

	var/new_regular_pay

/datum/contract_modification/regular_pay/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	new_regular_pay = input(user, "Enter the new regular pay for this contract:", "Regular Pay", parent.payment_amount) as num|null
	if(!isnum(new_regular_pay) || new_regular_pay < 0)
		to_chat(user, SPAN_WARNING("Invalid payment amount!"))
		new_regular_pay = null
		return FALSE

	return TRUE

/datum/contract_modification/regular_pay/mod_message(datum/network_contract/parent)
	return "The regular pay of the contract has been changed to [parent.format_value(new_regular_pay)]"

/datum/contract_modification/regular_pay/execute(datum/network_contract/parent, datum/computer_network/network)
	parent.payment_amount = new_regular_pay

/datum/contract_modification/add_group
	name = "Add Group"

	var/added_group

/datum/contract_modification/add_group/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	var/list/valid_groups = parent.owner.get_authorized_groups(network)

	if(LAZYLEN(parent.groups))
		valid_groups -= parent.groups

	if(!length(valid_groups))
		to_chat(user, SPAN_WARNING("You do not have authorization to grant membership in any additional groups."))
		return FALSE

	added_group = input(user, "Select the group to add to the contract:", "Contract Groups") as null|anything in valid_groups

	if(!isnull(added_group))
		return TRUE

	return FALSE

/datum/contract_modification/add_group/mod_message(datum/network_contract/parent)
	return "The following group will now be granted by the contract: \'[added_group]\'"

/datum/contract_modification/add_group/execute(datum/network_contract/parent, datum/computer_network/network)
	LAZYDISTINCTADD(parent.groups, added_group)

/datum/contract_modification/remove_group
	name = "Remove Group"

	var/removed_group

/datum/contract_modification/remove_group/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	if(!LAZYLEN(parent.groups))
		return FALSE

	removed_group = input(user, "Select the group to remove from the contract:", "Contract Groups") as null|anything in parent.groups

	if(!isnull(removed_group))
		return TRUE

	return FALSE

/datum/contract_modification/remove_group/mod_message(datum/network_contract/parent)
	return "The following group will no longer be granted by the contract: \'[removed_group]\'"

/datum/contract_modification/remove_group/execute(datum/network_contract/parent, datum/computer_network/network)
	LAZYREMOVE(parent.groups, removed_group)

/datum/contract_modification/add_auth
	name = "Add Contract Authorization"

	var/weakref/added_auth

/datum/contract_modification/add_auth/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	var/list/owned_contracts = parent.owner.owned_contracts
	if(!LAZYLEN(owned_contracts))
		to_chat(user, SPAN_WARNING("You are not the owner of any contracts!"))
		return FALSE

	var/datum/network_contract/added_contract = input(user, "Select the contract to be authorized:", "Contract Authorization") as null|anything in owned_contracts

	if(!added_contract)
		return FALSE

	added_auth = weakref(added_contract)
	return TRUE

/datum/contract_modification/add_auth/mod_message(datum/network_contract/parent)
	var/datum/network_contract/auth = added_auth?.resolve()
	if(!istype(auth))
		return
	return "The following contract is now authorized for management by this contract: \'[auth.name]\'"

/datum/contract_modification/add_auth/execute(datum/network_contract/parent, datum/computer_network/network)
	var/datum/network_contract/auth = added_auth?.resolve()
	if(!istype(auth))
		return
	parent.add_auth_contract(auth)

/datum/contract_modification/remove_auth
	name = "Remove Contract Authorization"

	var/weakref/removed_auth

/datum/contract_modification/remove_auth/prompt_input(mob/user, datum/network_contract/parent, datum/computer_network/network)
	var/datum/network_contract/removed_contract = input(user, "Select the contract to be removed:", "Contract Authorization") as null|anything in parent.get_authorized_contracts()

	if(!removed_contract)
		return FALSE

	removed_auth = weakref(removed_contract)
	return TRUE

/datum/contract_modification/remove_auth/mod_message(datum/network_contract/parent)
	var/datum/network_contract/auth = removed_auth?.resolve()
	if(!istype(auth))
		return
	return "The following contract is no longer authorized for management by this contract: \'[auth.name]\'"

/datum/contract_modification/remove_auth/execute(datum/network_contract/parent, datum/computer_network/network)
	var/datum/network_contract/auth = removed_auth?.resolve()
	if(!istype(auth))
		return
	parent.remove_auth_contract(auth)

#undef MAX_NAME_LENGTH
