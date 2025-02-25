-- Functions
function generateUUID(length)
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    local uuid = ''
    for i = 1, length do
        local rand = math.random(#chars)
        uuid = uuid .. chars:sub(rand, rand)
    end
    return 'TICKET-'..string.upper(uuid)
end

local function formatDate(dateStr)
    local year, month, day = dateStr:match("(%d+)-(%d+)-(%d+)")
    month = tonumber(month)
    day = tonumber(day)
    return string.format("%d/%d/%d", month, day, year)
end

local function getCurrentFormattedDate()
    local year = os.date("%Y")
    local month = tonumber(os.date("%m"))
    local day = tonumber(os.date("%d"))
    return string.format("%d/%d/%d", month, day, year)
end

function isDatePassed(dateStr)
    local function parseDate(dateStr)
        local year, month, day = dateStr:match("(%d+)-(%d+)-(%d+)")
        return os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 0, min = 0, sec = 0})
    end

    local dbDate = parseDate(dateStr)
    local currentDate = os.time()
    local sevenDaysInSeconds = 7 * 24 * 60 * 60
    return currentDate - dbDate >= sevenDaysInSeconds
end

function generateMessageFromResult(result)
    local author = result[1].author
    local title = result[1].title
    local details = result[1].details
    details = details:gsub("<[^>]+>", ""):gsub("&nbsp;", "")
    local message = "Author: " .. author .. "\n"
    message = message .. "Title: " .. title .. "\n"
    message = message .. "Details: " .. details
    return message
end

function insertIntoMDT(fullname, title, information, tags, officers, civilians, evidence, associated, time)
	exports.oxmysql:insert('INSERT INTO `mdt_incidents` (`author`, `title`, `details`, `tags`, `officersinvolved`, `civsinvolved`, `evidence`, `time`, `jobtype`) VALUES (:author, :title, :details, :tags, :officersinvolved, :civsinvolved, :evidence, :time, :jobtype)',
	{
		author = fullname,
		title = title,
		details = information,
		tags = json.encode(tags),
		officersinvolved = json.encode(officers),
		civsinvolved = json.encode(civilians),
		evidence = json.encode(evidence),
		time = time,
		jobtype = 'police',
	}, function(infoResult)
		if infoResult then
			exports.oxmysql:query('SELECT `author`, `title`, `details` FROM `mdt_incidents` WHERE `id` = @id', { ['@id'] = infoResult }, function(result)
				if result and #result > 0 then
					local message = generateMessageFromResult(result)
					
					for i=1, #associated do
						local associatedData = {
							cid = associated[i]['Cid'],
							linkedincident = associated[i]['LinkedIncident'],
							warrant = associated[i]['Warrant'],
							guilty = associated[i]['Guilty'],
							processed = associated[i]['Processed'],
							associated = associated[i]['Isassociated'],
							charges = json.encode(associated[i]['Charges']),
							fine = tonumber(associated[i]['Fine']),
							sentence = tonumber(associated[i]['Sentence']),
							recfine = tonumber(associated[i]['recfine']),
							recsentence = tonumber(associated[i]['recsentence']),
							time = associated[i]['Time'],
							officersinvolved = officers,
							civsinvolved = civilians
						}
					end
				else
					print('No incident found in the mdt_incidents table with id: ' .. infoResult)
				end
			end)
			
			for i=1, #associated do
				exports.oxmysql:insert('INSERT INTO `mdt_convictions` (`cid`, `linkedincident`, `warrant`, `guilty`, `processed`, `associated`, `charges`, `fine`, `sentence`, `recfine`, `recsentence`, `time`) VALUES (:cid, :linkedincident, :warrant, :guilty, :processed, :associated, :charges, :fine, :sentence, :recfine, :recsentence, :time)', {
					cid = associated[i]['Cid'],
					linkedincident = infoResult,
					warrant = associated[i]['Warrant'],
					guilty = associated[i]['Guilty'],
					processed = associated[i]['Processed'],
					associated = associated[i]['Isassociated'],
					charges = json.encode(associated[i]['Charges']),
					fine = tonumber(associated[i]['Fine']),
					sentence = tonumber(associated[i]['Sentence']),
					recfine = tonumber(associated[i]['recfine']),
					recsentence = tonumber(associated[i]['recsentence']),
					time = time,
					officersinvolved = officers,
					civsinvolved = civilians
				})
			end
		end
	end)
end

function checkDatesFromDatabase()
    exports.oxmysql:query('SELECT * FROM traffic_tickets WHERE paid = ?', {0}, function(results)
        for i, result in ipairs(results) do
            local dateStr = result.date
			local offenderCSN = result.offender_csn ~= nil and result.offender_csn ~= ""
			if isDatePassed(dateStr) and offenderCSN then
                print("7 days have passed for date: " .. dateStr)
				local title = result.offender_name.." - Unpaid Citation - "..getCurrentFormattedDate()
				local information = "<b>Unpaid Citation ("..result.ticketUUID..") of $"..result.total_fine..'</b>'
				local tagLine = 'Unpaid Citation ('..result.ticketUUID..')'
				local tags = { tagLine }
				local officers = { '('..result.badge_number..') '..result.officer_name }
				local associated = {
					{
						Processed = false,
						Charges = {
							[1] = "Failure to Appear"
						},
						Warrant = true,
						Sentence = 25,
						recfine = 9500,
						Cid = result.offender_csn,
						Fine = tonumber(result.total_fine) + 9500,
						Guilty = true,
						recsentence = 25,
						Isassociated = false
					}
				}
				local time = os.time() * 1000
				local fetchedInfo = exports.oxmysql:scalarSync('SELECT tags FROM mdt_incidents WHERE tags LIKE ?', {'%'..tagLine..'%'})
				if not fetchedInfo then
					insertIntoMDT(result.officer_name, title, information, tags, officers, {}, {}, associated, time)
				end
				-- TODO --
				-- Make SQL Statement to get the Incident Report Regarding The Traffic Ticket (SELECT TAG BASED ON TICKET UUID)
				-- Make SQL Statement to get LinkedIncident from mdt_convictions
				-- Then check if Incident Report & LinkedIncident match if so just update the status to WARRANT.
            end
        end
    end)
end

function getMonthsForOffense(offenseDescription)
    for _, offense in pairs(Config.Offenses) do
        if offense.offenseDescription == offenseDescription then
            return offense.months or 0
        end
    end
    return 0
end

function doIncidentReport(ticketData, offenderCSN)
	local title = ticketData.offender_name.." - Traffic Citation - "..getCurrentFormattedDate()
	local information = ticketData.notes
	local tagLine = 'Traffic Citation ('..ticketData.ticketUUID..')'
	local tags = { tagLine }
	
	local totalFine = exports.oxmysql:scalarSync('SELECT total_fine FROM traffic_tickets WHERE ticketUUID = ?', { ticketData.ticketUUID })
	local badgeNumber = exports.oxmysql:scalarSync('SELECT badge_number FROM traffic_tickets WHERE ticketUUID = ?', { ticketData.ticketUUID })
	local officerName = exports.oxmysql:scalarSync('SELECT officer_name FROM traffic_tickets WHERE ticketUUID = ?', { ticketData.ticketUUID })
	
	local officers = { '('..badgeNumber..') '..officerName }
	
	local charges = {}
	local totalMonths = 0
	
	if ticketData.offense1_description and ticketData.offense1_description ~= '' then
		table.insert(charges, ticketData.offense1_description)
		totalMonths = totalMonths + getMonthsForOffense(ticketData.offense1_description)
	end
	if ticketData.offense2_description and ticketData.offense2_description ~= '' then
		table.insert(charges, ticketData.offense2_description)
		totalMonths = totalMonths + getMonthsForOffense(ticketData.offense2_description)
	end
	if ticketData.offense3_description and ticketData.offense3_description ~= '' then
		table.insert(charges, ticketData.offense3_description)
		totalMonths = totalMonths + getMonthsForOffense(ticketData.offense3_description)
	end
	
	local associated = {
		{
			Processed = false,
			Charges = charges,
			Warrant = false,
			Sentence = 0,
			recfine = tonumber(totalFine),
			Cid = offenderCSN,
			Fine = tonumber(totalFine),
			Guilty = true,
			recsentence = totalMonths,
			Isassociated = false
		}
	}
	local time = os.time() * 1000
	local fetchedInfo = exports.oxmysql:scalarSync('SELECT tags FROM mdt_incidents WHERE tags LIKE ?', {'%'..tagLine..'%'})
	if not fetchedInfo then
		insertIntoMDT(officerName, title, information, tags, officers, {}, {}, associated, time)
	end
end

function doesIncidentExist(ticketUUID)
	local tagLine = 'Traffic Citation ('..ticketUUID..')'
	local fetchedInfo = exports.oxmysql:scalarSync('SELECT tags FROM mdt_incidents WHERE tags LIKE ?', {'%'..tagLine..'%'})
	if fetchedInfo then
		return true
	else
		return false
	end
end

-- Callbacks
-- Generate Ticket UUID
lib.callback.register('hidden-traffictickets:server:generateUUID', function()
    return generateUUID(16)
end)

-- Get Players
lib.callback.register('hidden-traffictickets:server:getPlayers', function()
    local players = {}
    local playerList = exports.qbx_core:GetQBPlayers()
  
    for _, player in pairs(playerList) do
        if player then
            local playerData = player.PlayerData
            table.insert(players, {
                name = playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname
            })
        end
    end
    return players
end)

-- Get Officer
lib.callback.register('hidden-traffictickets:server:getOfficer', function()
    local player = exports.qbx_core:GetPlayer(source)
    local officerData = {}

    if player then
        local playerData = player.PlayerData

        if playerData.job.name == 'police' then
            officerData = {
                officer_name = playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname,
                badge_number = playerData.metadata.callsign,
            }
        end
    end
    return officerData
end)

-- Events
RegisterNetEvent('hidden-traffictickets:server:doCitation', function(ticketData)
    local player = exports.qbx_core:GetPlayer(source)

    if player then
        if ticketData then
			local officerName = ticketData.badge_number..' | '..ticketData.officer_name
			exports.ox_inventory:RemoveItem(source, 'citation', 1, nil)
            exports.ox_inventory:AddItem(source, 'citation', 2, { ticketUUID = ticketData.ticketUUID, offenderName = ticketData.offender_name, officerName = officerName })
            Wait(200)
            
            exports.oxmysql:insert('INSERT INTO traffic_tickets (ticketUUID, offender_name, date, time, street, postal, license_plate, vehicle_make, vehicle_color, vehicle_type, speed, speed_zone, speed_type, officer_name, badge_number, agency, offense1_code, offense1_description, offense2_code, offense2_description, offense3_code, offense3_description, total_fine, officer_signature, offender_signature, notes, offender_csn, officer_csn, paid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
                ticketData.ticketUUID,
                ticketData.offender_name,
                ticketData.date,
                ticketData.time,
                ticketData.street,
                ticketData.postal,
                ticketData.license_plate,
                ticketData.vehicle_make,
                ticketData.vehicle_color,
                ticketData.vehicle_type,
                ticketData.speed,
                ticketData.speed_zone,
                ticketData.speed_type,
                ticketData.officer_name,
                ticketData.badge_number,
                ticketData.agency,
                ticketData.offense1_code,
                ticketData.offense1_description,
                ticketData.offense2_code,
                ticketData.offense2_description,
                ticketData.offense3_code,
                ticketData.offense3_description,
                ticketData.total_fine,
                ticketData.officer_signature,
                ticketData.offender_signature,
                ticketData.notes,
				nil,
				player.PlayerData.citizenid,
				0
            })
        else
            exports.ox_inventory:AddItem(source, 'citation', 1, nil)    
        end
    end
end)

RegisterNetEvent('hidden-traffictickets:server:fetchTicketData', function(ticketUUID, offenderName, officerName)
    local src = source
    if ticketUUID then
        exports.oxmysql:query('SELECT * FROM traffic_tickets WHERE ticketUUID = ?', { ticketUUID }, function(data)
            if data and #data > 0 then
                TriggerClientEvent('hidden-traffictickets:client:retrieveTicketData', src, data[1])
            else
				exports.ox_inventory:RemoveItem(src, 'citation', 1, { ticketUUID = ticketUUID, offenderName = offenderName, officerName = officerName })
                --exports.ox_inventory:RemoveItem(src, 'citation', 1, { ticketUUID = ticketUUID })
            end
        end)
    end
end)

RegisterNetEvent('hidden-traffictickets:server:updateCitation', function(ticketData)
	local player = exports.qbx_core:GetPlayer(source)
	
	if player then
		local csn = player.PlayerData.citizenid
		if ticketData then
			local data = ticketData.formData
			
			local ticketUUID = data.ticketUUID
			local signature = data.offender_signature
			
			local officer = exports.oxmysql:scalarSync('SELECT officer_csn FROM traffic_tickets WHERE ticketUUID = ?', { ticketUUID })
			if officer then
				if officer ~= csn then
					if not doesIncidentExist(ticketUUID) then
						exports.oxmysql:update('UPDATE traffic_tickets SET offender_signature = ?, offender_csn = ? WHERE ticketUUID = ?', { signature, csn, ticketUUID })
						doIncidentReport(data, csn)
					end
				end
			end
		end
	end
end)

RegisterNetEvent('hidden-traffictickets:server:fetchCitations', function()
    local src = source

    local player  = exports.qbx_core:GetPlayer(source)
    local csn = player.PlayerData.citizenid
    
    exports.oxmysql:query('SELECT * FROM traffic_tickets WHERE offender_csn = ? AND paid = ?', { csn, 0 }, function(data)
        if data and #data > 0 then
            TriggerClientEvent('hidden-traffictickets:client:retrieveCitations', src, data)
        else
            TriggerClientEvent('QBCore:Notify', src, "You have no outstanding citations.", "error", 3500)
        end
    end)
end)

RegisterNetEvent('hidden-traffictickets:server:fetchCommissions', function()
    local src = source

    local player  = exports.qbx_core:GetPlayer(source)
    local csn = player.PlayerData.citizenid
    
    exports.oxmysql:query('SELECT * FROM traffic_commission WHERE officer_csn = ?', { csn }, function(data)
        if data and #data > 0 then
            TriggerClientEvent('hidden-traffictickets:client:retrieveCommissions', src, data)
        else
            TriggerClientEvent('QBCore:Notify', src, "You have no pending commission due.", "error", 3500)
        end
    end)
end)

RegisterNetEvent('hidden-traffictickets:server:payCitation', function(ticketUUID)
    local src = source
    local player  = exports.qbx_core:GetPlayer(source)
	
	local offenderName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname

    if ticketUUID then
        local fetchedFine = exports.oxmysql:scalarSync('SELECT total_fine FROM traffic_tickets WHERE ticketUUID = ?', { ticketUUID })
		local officerName = exports.oxmysql:scalarSync('SELECT officer_name FROM traffic_tickets WHERE ticketUUID = ?', { ticketUUID })
		local officerCSN = exports.oxmysql:scalarSync('SELECT officer_csn FROM traffic_tickets WHERE ticketUUID = ?', { ticketUUID })
        local totalFine = tonumber(fetchedFine)

        if player.Functions.RemoveMoney('bank', totalFine, 'paid-citation-'..ticketUUID) then
            --exports.oxmysql:update('DELETE FROM traffic_tickets WHERE ticketUUID = ?', { ticketUUID })
			exports.oxmysql:update('UPDATE traffic_tickets SET paid = ? WHERE ticketUUID = ?', { 1, ticketUUID })
            TriggerClientEvent('QBCore:Notify', src, "You have successfully paid your citation.", "success", 3500)
			
			local commission = totalFine * 0.15
			local toPDFund = totalFine - commission

			exports.qbx_management:AddMoney("police", toPDFund)
			exports.oxmysql:insert('INSERT INTO traffic_commission (ticketUUID, offender_name, officer_name, officer_csn, commission) VALUES (?, ?, ?, ?, ?)', { ticketUUID, offenderName, officerName, officerCSN, commission })
        else
            TriggerClientEvent('QBCore:Notify', src, "You do not have enough money to pay this citation!", "error", 3500)
        end
    end
end)

RegisterNetEvent('hidden-traffictickets:server:collectOfficerCommission', function(ticketUUID)
    local player = exports.qbx_core:GetPlayer(source)

    if player then
        local playerData = player.PlayerData
		local officerName = playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname
		local commission = exports.oxmysql:scalarSync('SELECT commission FROM traffic_commission WHERE ticketUUID = ?', { ticketUUID })
		
		player.Functions.AddMoney('bank', commission, "fine-commission")
		TriggerClientEvent('QBCore:Notify', playerData.source, 'A commission of $'..commission..' has been deposited into your bank account!', 'success')
		exports.oxmysql:update('DELETE FROM traffic_commission WHERE ticketUUID = ?', { ticketUUID })
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
	if (GetCurrentResourceName() ~= resourceName) then
		return
	end
	checkDatesFromDatabase()
end)