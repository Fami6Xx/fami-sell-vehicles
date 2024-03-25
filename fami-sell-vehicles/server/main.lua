lib.locale()

lib.callback.register('fami-sell-vehicles:checkCar', function (source)
    local xPlayer = ESX.GetPlayerFromId(source)
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
    if vehicle == 0 then return false end
    if not DoesEntityExist(vehicle) then return false end
    local plate = GetVehicleNumberPlateText(vehicle)

    MySQL.Async.fetchAll('SELECT * FROM owned_vehicles WHERE owner = @owner AND plate = @plate LIMIT 1', {
        ['@owner'] = xPlayer.getIdentifier(),
        ['@plate'] = plate
    }, function (result)
        if result[1] then
            return true
        else
            return false
        end
    end)
end)

lib.callback.register('fami-sell-vehicles:putOnSale', function(source, money, vehicle, vehicleProps)
    local xPlayer = ESX.GetPlayerFromId(source)
    local plate = vehicleProps.plate
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
    if vehicle == 0 then return false end
    if not DoesEntityExist(vehicle) then return false end
    local vehPlate = GetVehicleNumberPlateText(vehicle)
    if vehPlate ~= plate then return false end

    MySQL.insert.await('INSERT INTO vehicles_for_sale (seller, vehicleProps, price) VALUES (@seller, @vehicleProps, @price)', {
        ['@seller'] = xPlayer.getIdentifier(),
        ['@price'] = money,
        ['@vehicleProps'] = json.encode(vehicleProps)
    })

    MySQL.update.await('DELETE FROM owned_vehicles WHERE plate = @plate', {
        ['@plate'] = plate
    })

    return true
end)

lib.callback.register('fami-sell-vehicles:getNumberOfCars', function (source)
    local xPlayer = ESX.GetPlayerFromId(source)
    local plate = GetVehicleNumberPlateText(GetVehiclePedIsIn(GetPlayerPed(source), false))

    local result = MySQL.query.await('SELECT COUNT(*) FROM vehicles_for_sale')

    return result
end)

lib.callback.register('fami-sell-vehicles:getVehicleForSale', function (source, index)
    if index ~= '0' then
        index = tonumber(index)
    else
        index = 0
    end

    if index == nil then
        error("Invalid index")
    end

    local result = MySQL.query.await('SELECT vehicleProps, seller, price FROM vehicles_for_sale LIMIT 1 OFFSET @index', {
        ['@index'] = index
    })

    return result
end)

lib.callback.register('fami-sell-vehicles:getVehiclesForSale', function (source)
    local result = MySQL.query.await('SELECT * FROM vehicles_for_sale')

    local id = 0
    for k, v in pairs(result) do
        v.id = id
        id = id + 1
    end

    return result
end)


function UpdateCash(identifier, cash)
	local xPlayer = ESX.GetPlayerFromIdentifier(identifier)

	if xPlayer ~= nil then
		xPlayer.addAccountMoney("bank", cash)

        xPlayer.showNotification(locale('vehicle_sold', cash))
	else
		MySQL.Async.fetchAll('SELECT accounts FROM users WHERE identifier = @identifier', { ["@identifier"] = identifier }, function(result)
		    if result[1]["accounts"] ~= nil then
	       		local accountsData = json.decode(result[1]["accounts"]) 
        			accountsData["bank"] = accountsData["bank"] + cash

        			MySQL.Async.execute("UPDATE users SET accounts = @newBank WHERE identifier = @identifier",
            		{
                			["@identifier"] = identifier,
                			["@newBank"] = json.encode(accountsData) 
            		})
    		    end
		end)
	end
end

Trim = function(word)
	if word ~= nil then
		return word:match("^%s*(.-)%s*$")
	else
		return nil
	end
end