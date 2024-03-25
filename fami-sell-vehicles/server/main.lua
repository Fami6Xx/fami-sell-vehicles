lib.locale()

lib.callback.register('fami-sell-vehicles:checkCar', function (source, vehicle, vehiclePlate)
    local xPlayer = ESX.GetPlayerFromId(source)

    local response = MySQL.query.await('SELECT owner FROM owned_vehicles WHERE owner = @owner AND plate = @plate LIMIT 1', {
        ['@owner'] = xPlayer.getIdentifier(),
        ['@plate'] = vehiclePlate
    })

    if response then
        if #response > 0 then
            return true
        else
            return false
        end
    else
        return false
    end
end)

lib.callback.register('fami-sell-vehicles:putOnSale', function(source, money, vehicle, vehicleProps)
    local xPlayer = ESX.GetPlayerFromId(source)
    local plate = vehicleProps.plate
    local pedVehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
    print(pedVehicle, vehicle)
    if pedVehicle == 0 then return false end
    print("1")
    if pedVehicle ~= vehicle then return false end
    print("2")
    if not DoesEntityExist(vehicle) then return false end
    print("3")
    if not vehicleProps then return false end
    print("4")

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

RegisterNetEvent('fami-sell-vehicles:buyVehicle')
AddEventHandler('fami-sell-vehicles:buyVehicle', function (index)
    local xPlayer = ESX.GetPlayerFromId(source)

    print(index)

    if index ~= '0' then
        index = tonumber(index)
    else
        index = 0
    end

    if index == nil then
        error("Invalid index")
    end

    local result = MySQL.query.await('SELECT id, vehicleProps, seller, price FROM vehicles_for_sale LIMIT 1 OFFSET @index', {
        ['@index'] = index
    })

    if result[1] then
        local vehicleProps = json.decode(result[1].vehicleProps)
        local seller = result[1].seller
        local price = result[1].price

        if xPlayer.getMoney() >= price then
            xPlayer.removeMoney(price)
            UpdateCash(seller, price - (price * (Config.SellCarTax or 0.1)))

            MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle, `stored`, type) VALUES (@owner, @plate, @vehicle, 1, "car")', {
                ['@owner'] = xPlayer.getIdentifier(),
                ['@plate'] = vehicleProps.plate,
                ['@vehicle'] = json.encode(vehicleProps)
            })

            MySQL.update.await('DELETE FROM vehicles_for_sale WHERE id = @id', {
                ['@id'] = result[1].id
            })

            TriggerClientEvent('fami-sell-vehicles:removedVehicle', -1, index)

            xPlayer.showNotification(locale('vehicle_bought', price))
        else
            xPlayer.showNotification(locale('not_enough_money'))
        end
    end
end)

RegisterNetEvent('fami-sell-vehicles:returnVehicle')
AddEventHandler('fami-sell-vehicles:returnVehicle', function (index)
    local xPlayer = ESX.GetPlayerFromId(source)

    if index ~= '0' then
        index = tonumber(index)
    else
        index = 0
    end

    if index == nil then
        error("Invalid index")
    end

    local result = MySQL.query.await('SELECT id, vehicleProps, seller, price FROM vehicles_for_sale LIMIT 1 OFFSET @index', {
        ['@index'] = index
    })

    if result[1] then
        local vehicleProps = json.decode(result[1].vehicleProps)
        local seller = result[1].seller
        if seller ~= xPlayer.getIdentifier() then
            xPlayer.showNotification(locale('not_your_vehicle'))
            return
        end

        MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle, `stored`, type) VALUES (@owner, @plate, @vehicle, 1, "car")', {
            ['@owner'] = seller,
            ['@plate'] = vehicleProps.plate,
            ['@vehicle'] = json.encode(vehicleProps)
        })

        MySQL.update.await('DELETE FROM vehicles_for_sale WHERE id = @id', {
            ['@id'] = result[1].id
        })

        TriggerClientEvent('fami-sell-vehicles:removedVehicle', -1, index)

        xPlayer.showNotification(locale('vehicle_returned'))
    end
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