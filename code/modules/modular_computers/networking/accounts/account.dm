/datum/computer_file/data/account
	filetype = "ACT"
	var/login = ""
	var/password = ""

	var/can_login = TRUE	// Whether you can log in with this account. Set to false for system accounts
	var/suspended = FALSE	// Whether the account is banned by the SA.
	var/list/logged_in_os = list() // OS which are currently logged into this account. Used for e-mail notifications, currently.

	var/list/groups = list() // Groups which this account is a member of.
	var/list/parent_groups = list() // Parent groups with a child/children which this account is a member of.

	var/fullname	= "N/A"

	// E-Mail
	var/list/inbox = list()
	var/list/outbox = list()
	var/list/spam = list()
	var/list/deleted = list()

	var/broadcaster = FALSE // If sent to true, e-mails sent to this address will be automatically sent to all other accounts in the network.

	var/notification_mute = FALSE
	var/notification_sound = "*beep*"
	var/backup = FALSE // Backups are not returned when searching for accounts, but can be recovered using the accounts program.

	// Finances
	var/datum/money_account/child/network/money_account

	var/routing_login
	var/routing_network
	var/routing_pin

	var/list/datum/network_contract/owned_contracts
	var/list/datum/contract_instance/held_contracts

	var/list/pending_contracts

	// Reference to the contract instance currently clocked in as
	var/weakref/clocked_in

	copy_string = "(Backup)"

/datum/computer_file/data/account/calculate_size()
	size = 1
	for(var/datum/computer_file/data/email_message/stored_message in all_emails())
		stored_message.calculate_size()
		size += stored_message.size

/datum/computer_file/data/account/New(_login, _password, _fullname)
	if(_login)
		login = _login
		stored_data = "[login]"
	if(_password)
		password = _password
	if(_fullname)
		fullname = _fullname
	if(filename == initial(filename))
		filename = "account[random_id(type, 100,999)]"
	..()

/datum/computer_file/data/account/Destroy()
	for(var/weakref/os_ref in logged_in_os)
		var/datum/extension/interactive/os/os = os_ref.resolve()
		if(os.login == login)
			os.logout_account()

	logged_in_os.Cut()
	groups.Cut()
	parent_groups.Cut()

	if(money_account)
		money_account.on_escrow(TRUE) // Don't bother sending an e-mail since it's about to be deleted anyway.
		QDEL_NULL(money_account)

	QDEL_NULL_LIST(inbox)
	QDEL_NULL_LIST(outbox)
	QDEL_NULL_LIST(spam)
	QDEL_NULL_LIST(deleted)

	QDEL_NULL_LIST(owned_contracts)
	. = ..()

/datum/computer_file/data/account/proc/all_emails()
	return (inbox | spam | deleted | outbox)

/datum/computer_file/data/account/proc/all_incoming_emails()
	return (inbox | spam | deleted)

/datum/computer_file/data/account/proc/receive_mail(datum/computer_file/data/email_message/received_message)
	inbox.Add(received_message)

	for(var/weakref/os_ref in logged_in_os)
		var/datum/extension/interactive/os/os = os_ref.resolve()
		if(istype(os))
			os.mail_received(received_message)
		else
			logged_in_os -= os_ref

// Returns a financial account able to accept/send payments from this network account.
/datum/computer_file/data/account/proc/get_financial_account(datum/computer_network/searching)
	// Prioritize the routed account.
	if(routing_login && routing_network)
		var/datum/money_account/routed = searching?.get_financial_account(routing_login, routing_network)
		if(istype(routed))
			if(routed.security_level < 1 || (routed.remote_access_pin == routing_pin))
				return routed

	return money_account

// Returns contracts the account is allowed to grant/revoke, but not necessarily modify
/datum/computer_file/data/account/proc/get_authorized_contracts()
	. = list()
	if(LAZYLEN(owned_contracts))
		. += owned_contracts

	if(LAZYLEN(held_contracts))
		for(var/datum/contract_instance/instance in held_contracts)
			var/datum/network_contract/parent = instance.parent
			. |= parent.get_authorized_contracts()

// Returns the contract instances the account is party to
// TODO: Remove or add check for validity if necessary.
/datum/computer_file/data/account/proc/get_held_contracts()
	. = list()
	for(var/datum/contract_instance/instance in held_contracts)
		. += instance

/datum/computer_file/data/account/proc/get_held_contract_parents()
	. = list()
	for(var/datum/contract_instance/instance in held_contracts)
		. += instance.parent

/datum/computer_file/data/account/proc/get_pending_contracts()
	. = list()
	for(var/list/pending_tuple in pending_contracts)
		var/weakref/pending_ref = pending_tuple[1]
		var/datum/network_contract/pending = pending_ref.resolve()
		if(!istype(pending))
			LAZYREMOVE(pending_contracts, list(pending_tuple))
			continue
		. += pending

/datum/computer_file/data/account/proc/clock_in(datum/contract_instance/instance)
	if(clocked_in)
		var/datum/contract_instance/clock_instance = clocked_in.resolve()
		if(istype(clock_instance))
			clock_instance.clock_out()
		clocked_in = null

	instance.clock_in()
	clocked_in = weakref(instance)

/datum/computer_file/data/account/proc/clock_out()
	if(clocked_in)
		var/datum/contract_instance/instance = clocked_in.resolve()
		if(istype(instance))
			instance.clock_out()

	clocked_in = null

/datum/computer_file/data/account/proc/get_active_job_title()
	if(!clocked_in)
		return

	var/datum/contract_instance/instance = clocked_in.resolve()
	if(!istype(instance))
		clock_out()
		return
	return instance.parent?.job_title

/datum/computer_file/data/account/proc/get_access(datum/computer_network/network, ignore_contracts = FALSE)
	if(!istype(network) || !(src in network.get_accounts_unsorted()))
		return
	. = list()
	var/location = "[network.network_id]"
	. += "[login]@[location]" // User access uses '@'
	for(var/group in groups)
		. |= "[group].[location]"	// Group access uses '.'
	for(var/group in parent_groups) // Membership in a child group grants access to anything with an access requirement set to the parent group.
		. |= "[group].[location]"

	// Check for access granted via contract.
	if(ignore_contracts)
		return
	for(var/datum/contract_instance/instance in get_held_contracts())
		var/datum/network_contract/parent = instance.parent
		if(!parent || !length(parent.groups))
			continue

		if(parent.require_clockin && (clocked_in != weakref(instance)))
			continue

		for(var/group in parent.get_granted_groups(network))
			. |= "[group].[location]"

// Gets the groups this account is authorized to grant by owner contract or manual assignment.
/datum/computer_file/data/account/proc/get_authorized_groups(datum/computer_network/network)
	. = list()
	var/datum/extension/network_device/acl/net_acl = network.access_controller
	if(!net_acl)
		return

	// Unfortunately, we must ignore contracts to avoid infinite loops.
	if(net_acl.has_access(get_access(network, ignore_contracts = TRUE)))
		return net_acl.get_all_groups()

	if(net_acl.allow_submanagement)
		var/list/group_dict = net_acl.get_group_dict()
		for(var/parent_group in group_dict)
			var/list/child_groups = group_dict[parent_group]
			if(length(child_groups))
				if(parent_group in groups)
					. |= child_groups

/datum/computer_file/data/account/Clone(rename)
	. = ..(TRUE) // We always rename the file since a copied account is always a backup.

/datum/computer_file/data/account/PopulateClone(datum/computer_file/data/account/clone)
	clone = ..()
	clone.backup        = TRUE
	clone.login         = login
	clone.password      = password
	clone.can_login     = can_login
	clone.suspended     = suspended
	clone.groups        = groups.Copy()
	clone.parent_groups = parent_groups.Copy()
	clone.fullname      = fullname

	// TODO: Don't backup e-mails for now - they are themselves other files which makes this complicated. In the future
	// accounts will point to e-mails stored seperately on a server.
	return clone

// Address namespace (@internal-services.net) for email addresses with special purpose only!.
/datum/computer_file/data/account/service
	can_login = FALSE

/datum/computer_file/data/account/service/broadcaster
	login = EMAIL_BROADCAST
	broadcaster = TRUE

/datum/computer_file/data/account/service/document
	login = EMAIL_DOCUMENTS

/datum/computer_file/data/account/service/sysadmin
	login = EMAIL_SYSADMIN