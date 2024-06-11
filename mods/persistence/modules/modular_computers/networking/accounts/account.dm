SAVED_VAR(/datum/computer_file/data/account, login)
SAVED_VAR(/datum/computer_file/data/account, password)
SAVED_VAR(/datum/computer_file/data/account, can_login)
SAVED_VAR(/datum/computer_file/data/account, suspended)
SAVED_VAR(/datum/computer_file/data/account, groups)
SAVED_VAR(/datum/computer_file/data/account, parent_groups)
SAVED_VAR(/datum/computer_file/data/account, fullname)
SAVED_VAR(/datum/computer_file/data/account, inbox)
SAVED_VAR(/datum/computer_file/data/account, outbox)
SAVED_VAR(/datum/computer_file/data/account, spam)
SAVED_VAR(/datum/computer_file/data/account, deleted)
SAVED_VAR(/datum/computer_file/data/account, backup)
SAVED_VAR(/datum/computer_file/data/account, money_account)

/datum/contract_instance/before_save()
	. = ..()
	// Update the hour count prior to save so no time is lost on load, since we don't save clocked in status.
	if(holder && last_hour_count && (holder.clocked_in?.resolve() == src))
		var/time_delta = SSmoney_accounts.get_current_time() - last_hour_count
		hour_counter += time_delta
		last_hour_count = SSmoney_accounts.get_current_time()

// Persistence
SAVED_VAR(/datum/contract_instance, name)
SAVED_VAR(/datum/contract_instance, authorizer)
SAVED_VAR(/datum/contract_instance, last_pay)

SAVED_VAR(/datum/contract_instance, hour_counter)

// Persistence
SAVED_VAR(/datum/network_contract, name)
SAVED_VAR(/datum/network_contract, groups)
SAVED_VAR(/datum/network_contract, job_title)
SAVED_VAR(/datum/network_contract, hourly_pay)
SAVED_VAR(/datum/network_contract, require_clockin)
SAVED_VAR(/datum/network_contract, payment_period)
SAVED_VAR(/datum/network_contract, payment_amount)
SAVED_VAR(/datum/network_contract, reversed_payment)
SAVED_VAR(/datum/network_contract, authorized_contracts)
SAVED_VAR(/datum/network_contract, instances)
SAVED_VAR(/datum/network_contract, additional_clauses)
SAVED_VAR(/datum/network_contract, finalized)

/datum/network_contract/after_deserialize()
	// Do this to limit circular references
	for(var/datum/contract_instance/instance in instances)
		instance.parent = src
	. = ..()

// Persistence
SAVED_VAR(/datum/computer_file/data/account, routing_login)
SAVED_VAR(/datum/computer_file/data/account, routing_network)
SAVED_VAR(/datum/computer_file/data/account, routing_pin)

// We intentionally do not save clocked-in status
SAVED_VAR(/datum/computer_file/data/account, owned_contracts)
SAVED_VAR(/datum/computer_file/data/account, held_contracts)
SAVED_VAR(/datum/computer_file/data/account, pending_contracts)

/datum/computer_file/data/account/after_deserialize()
	. = ..()
	// Do this to limit circular references
	for(var/datum/network_contract/contract in owned_contracts)
		contract.owner = src

	for(var/datum/contract_instance/instance in held_contracts)
		instance.holder = src