-- Functions
local function toggleNuiFrame(shouldShow)
  SetNuiFocus(shouldShow, shouldShow)
  SendReactMessage('setVisible', shouldShow)
end

local function sendTicketData(ticketData)
  SendReactMessage('populateForm', ticketData)
  toggleNuiFrame(true)
end

local function createBoxZone()
  exports.ox_target:addBoxZone({
    coords = vector3(441.2357, -981.7198, 30.6896), -- MRPD
    size = vector3(3, 3, 3),
    rotation = 267.0452,
    debug = false,
    options = {
        {
            label = "Pay Citation",
            icon = "fas fa-box-archive",
            distance = 2.0,
            serverEvent = "hidden-traffictickets:server:fetchCitations",
        },
        {
            label = "View Commissions",
            icon = "fas fa-money-bill",
            distance = 2.0,
            serverEvent = "hidden-traffictickets:server:fetchCommissions",
			      groups = {'police'}
        }
    }
  })
end

-- NUI Callbacks
RegisterNUICallback('hideFrame', function(data, cb)
  toggleNuiFrame(false)
  cb({})
  exports["rpemotes"]:EmoteCancel(true)
end)

RegisterNUICallback('updateCitation', function(data, cb)
  toggleNuiFrame(false)
  TriggerServerEvent('hidden-traffictickets:server:updateCitation', data)
  cb({})
end)

RegisterNUICallback('getOffenses', function(data, cb)
  local offenses = {}

  for _, offense in pairs(Config.Offenses) do
      table.insert(offenses, {
          code = offense.offenseCode,
          description = offense.offenseDescription,
          fine = offense.fine
      })
  end

  cb(offenses)
end)

RegisterNUICallback('getPlayers', function(_, cb)
  local players = lib.callback.await('hidden-traffictickets:server:getPlayers')
  cb(players)
end)

RegisterNUICallback('getOfficer', function(_, cb)
  local officerData = lib.callback.await('hidden-traffictickets:server:getOfficer', source)
  cb(officerData)
end)

RegisterNUICallback('scanTicket', function(data, cb)
  local ticketUUID = lib.callback.await('hidden-traffictickets:server:generateUUID')
  data.ticketUUID = ticketUUID
  TriggerServerEvent("InteractSound_SV:PlayWithinDistance", 3.0, "scannerbeep", 0.10)
  TriggerServerEvent('hidden-traffictickets:server:doCitation', data)
  toggleNuiFrame(false)
  exports["rpemotes"]:EmoteCancel(true)
  cb(data)
end)

-- Metadata
exports.ox_inventory:displayMetadata({
    ticketUUID = 'Ticket UUID',
    offenderName = 'Offender',
	officerName = 'Issued By',
})

-- Events
AddEventHandler('onResourceStart', function(resourceName)
	if (GetCurrentResourceName() ~= resourceName) then
		return
	end
	createBoxZone()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
	createBoxZone()
end)

RegisterNetEvent('hidden-traffictickets:client:retrieveTicketData', function(ticketData)
  if ticketData then
    sendTicketData(ticketData)
  else
    toggleNuiFrame(false)
  end
end)

RegisterNetEvent('hidden-traffictickets:client:retrieveCitations', function(citations)
  if citations and #citations > 0 then
    local options = {}
    for _, citationData in ipairs(citations) do
      table.insert(options, {
        title = citationData.ticketUUID,
        description = 'Issued by: '..citationData.badge_number .. ' | ' .. citationData.officer_name,
        onSelect = function()
          local alert = lib.alertDialog({
            header = 'Pay Citation',
            content = 'Are you sure you want to pay this citation with a total price of: $'..citationData.total_fine..'?',
            centered = true,
            cancel = true,
            size = 'md',
          })
          if alert == 'confirm' then
            TriggerServerEvent('hidden-traffictickets:server:payCitation', citationData.ticketUUID)
          end
        end
      })
    end

    lib.registerContext({
      id = 'citations',
      title = 'View Citations',
      options = options,
    })

    lib.showContext('citations')
  end
end)

RegisterNetEvent('hidden-traffictickets:client:retrieveCommissions', function(commissions)
  if commissions and #commissions > 0 then
    local options = {}
    for _, commissionData in ipairs(commissions) do
      table.insert(options, {
        title = commissionData.ticketUUID,
        description = 'Paid by: '..commissionData.offender_name,
        onSelect = function()
			TriggerServerEvent('hidden-traffictickets:server:collectOfficerCommission', commissionData.ticketUUID)
        end
      })
    end

    lib.registerContext({
      id = 'commissions',
      title = 'View Commissions',
      options = options,
    })

    lib.showContext('commissions')
  end
end)

-- Item Exports
exports('citationRoll', function(data, slot)
	exports["rpemotes"]:EmoteCommandStart("uncuff", 0)
	TriggerServerEvent("InteractSound_SV:PlayWithinDistance", 3.0, "papertear", 0.3)
	exports.ox_inventory:useItem(data, function(data)
		if data then
			if lib.progressCircle({
				label = "Tearing Sheet...",
				duration = 1200,
				position = 'bottom',
				useWhileDead = false,
				canCancel = true,
			}) then
				exports["rpemotes"]:EmoteCancel(true)
				TriggerServerEvent('hidden-traffictickets:server:doCitation')
			else
				exports["rpemotes"]:EmoteCancel(true)
			end
		end
	end)
end)

exports('citation', function(data, slot)
	exports["rpemotes"]:EmoteCommandStart("notepad", 0)
	exports.ox_inventory:useItem(data, function(itemData)
		if itemData and itemData.metadata then
			local ticketUUID = itemData.metadata.ticketUUID
			local offenderName = itemData.metadata.offenderName
			local officerName = itemData.metadata.officerName

			if ticketUUID then
				TriggerServerEvent('hidden-traffictickets:server:fetchTicketData', ticketUUID, offenderName, officerName)
			else
				toggleNuiFrame(true)
			end
		end
	end)
end)
