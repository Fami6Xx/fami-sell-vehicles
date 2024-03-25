lib.locale()

local point, marker = nil, nil
local SellPointBlip = nil

local showPoint = nil
local showingVehicle = 0
local showingVehiclePrice = 0
local showingVehicleId = 0
local showingVehicleOwner = false
local deletingShowingVehicle = false
local loadingCar = false
local sellingCarTextPosition = vector3(0,0,0)

Citizen.CreateThread(function()
    SellPointBlip = AddBlipForCoord(Config.SellPoint.blipPos.x, Config.SellPoint.blipPos.y, Config.SellPoint.blipPos.z)
    SetBlipSprite(SellPointBlip, Config.SellPoint.blipSprite)
    SetBlipDisplay(SellPointBlip, 4)
    SetBlipScale(SellPointBlip, Config.SellPoint.blipScale)
    SetBlipColour(SellPointBlip, Config.SellPoint.blipColor)
    SetBlipAsShortRange(SellPointBlip, Config.SellPoint.blipShortRange)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(locale('blip_name'))
    EndTextCommandSetBlipName(SellPointBlip)

    point = lib.points.new({
        coords = Config.SellPoint.markerPos,
        distance = Config.SellPoint.markerShowRadius,
    })

    marker = lib.marker.new({
        type = Config.SellPoint.markerType,
        color = Config.SellPoint.markerColor,
        coords = Config.SellPoint.markerPos,
        width = Config.SellPoint.markerWidth,
        height = Config.SellPoint.markerHeight,
    })

    function point:nearby()
        marker:draw()

        if self.currentDistance <= 1.5 then
            if not lib.isTextUIOpen() then
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 then
                    if GetPedInVehicleSeat(vehicle, -1) == ped then
                        lib.showTextUI(locale('sell_vehicle_prompt'), {
                            position = "top-center"
                        })
                    end
                end
            end

            if IsControlJustPressed(0, 51) then
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle == 0 then
                    ESX.ShowNotification(locale('sell_vehicle_prompt_notinvehicle'), "error")
                    return
                end

                if GetPedInVehicleSeat(vehicle, -1) ~= ped then
                    ESX.ShowNotification(locale('sell_vehicle_prompt_notinvehicle'), "error")
                    return
                end

                lib.hideTextUI()
                local ownsVehicle = lib.callback.await('fami-sell-vehicles:checkCar', false)
                if not ownsVehicle then
                    ESX.ShowNotification(locale('sell_vehicle_not_owned'), "error")
                    return
                end
                local money = lib.inputDialog(locale('sell_vehicle_price_prompt_title'), {
                    {type = "number", label = locale('sell_vehicle_price_prompt_text'), icon = "dollar"}
                })
                if not money then return end
                if money[1] <= 0 then
                    ESX.ShowNotification(locale('sell_vehicle_price_invalid'), "error")
                    return
                end
                
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                local vehicleProperties = lib.getVehicleProperties(vehicle)
                local success = lib.callback.await('fami-sell-vehicles:putOnSale', false, money[1], vehicle, vehicleProperties)
                if success then
                    ESX.ShowNotification(locale('sell_vehicle_success', money[1]))
                    ESX.Game.DeleteVehicle(vehicle)
                else
                    ESX.ShowNotification(locale('sell_vehicle_error'), "error")
                end
            end
        else
            if lib.isTextUIOpen() then
                lib.hideTextUI()
            end
        end
    end
end)

Citizen.CreateThread(function ()
    showPoint = lib.points.new({
        coords = Config.ViewVehicles.position,
        distance = Config.ViewVehicles.spawnDistance,
    })

    function showPoint:onEnter()
        if deletingShowingVehicle then
            deletingShowingVehicle = false
            return
        end

        if showingVehicle ~= 0 then
            if DoesEntityExist(showingVehicle) then
                DeleteEntity(showingVehicle)
            end
            showingVehicle = 0
            showingVehicleId = 0
        end

        SpawnVehicle(showingVehicleId)
    end

    function showPoint:nearby()
        if self.currentDistance <= 6.5 then

            if not lib.isTextUIOpen() then
                lib.showTextUI(locale('view_vehicle_prompt'), {
                    position = "top-center"
                })
            end

            if IsControlJustPressed(0, 51) then
                lib.hideTextUI()
                if showingVehicle == -1 then
                    ESX.ShowNotification(locale('no_vehicle_for_sale'), "error")
                    return
                end

                lib.registerContext({
                    id = "fami-sell-vehicles:vehicleOptions",
                    title = locale('vehicle_options_title'),
                    canClose = true,
                    options = {
                        {title = locale('vehicle_options_buy', showingVehiclePrice), icon = "dollar", serverEvent = "fami-sell-vehicles:buyVehicle", args = showVehicleId},
                        {title = locale('vehicle_options_return'), icon = "car", serverEvent = "fami-sell-vehicles:returnVehicle", args = showVehicleId, disabled = showingVehicleOwner ~= ESX.PlayerData.identifier},
                        {title = locale('vehicle_options_change_vehicle'), icon = "car-side", onSelect = openAllVehiclesMenu},
                    }
                })

                lib.showContext("fami-sell-vehicles:vehicleOptions")
            end
        else
            if self.currentDistance <= 10 then
                if lib.isTextUIOpen() then
                    lib.hideTextUI()
                end
            end
        end
    end

    function showPoint:onExit()
        if loadingCar then
            deletingShowingVehicle = true
        end

        while loadingCar and deletingShowingVehicle do
            Citizen.Wait(1)
        end

        if showingVehicle ~= -1 or showingVehicle ~= 0 then
            if DoesEntityExist(showingVehicle) then
                DeleteEntity(showingVehicle)
                showingVehicle = 0
                showingVehicleId = 0
            end
        end
    end
end)

function SpawnVehicle(id)
    local vehicle = lib.callback.await('fami-sell-vehicles:getVehicleForSale', false, id)
    if vehicle == nil then
        showingVehicle = -1
        return
    end

    loadingCar = true
    local vehicleProps = json.decode(vehicle[1].vehicleProps)
    showingVehiclePrice = formatMoney(vehicle[1].price)
    showingVehicleOwner = vehicle[1].seller
    
    ESX.Game.SpawnLocalVehicle(vehicleProps.model, Config.ViewVehicles.position, Config.ViewVehicles.position.w, function (veh)
        lib.setVehicleProperties(veh, vehicleProps)
        SetVehicleLights(veh, 2)
        SetVehicleLightsMode(veh, 2)
        SetVehicleOnGroundProperly(veh)
        SetEntityCanBeDamaged(veh, false)
        FreezeEntityPosition(veh, true)

        showingVehicle = veh
        showingVehicleId = id
        
        local min, max = GetModelDimensions(GetEntityModel(veh))
        local height = max.z - min.z
        local location = GetEntityCoords(veh)
        sellingCarTextPosition = vector3(location.x, location.y, location.z + height + 0.3)
        loadingCar = false
    end)
end

Citizen.CreateThread(function ()
    while true do
        local sleep = 500
        local PlayerPed = ESX.PlayerData.ped
        local PlayerCoords = GetEntityCoords(PlayerPed)
        local distance = #(PlayerCoords - vector3(Config.ViewVehicles.position.x, Config.ViewVehicles.position.y, Config.ViewVehicles.position.z))
        if distance < Config.ViewVehicles.spawnDistance then
            sleep = 0
        else
            goto continue
        end
        if showingVehicle == -1 then
            ESX.Game.Utils.DrawText3D(Config.ViewVehicles.position, locale('no_vehicle_for_sale'), 1.0)
            goto continue
        end

        if loadingCar or showingVehiclePrice == 0 then
            ESX.Game.Utils.DrawText3D(Config.ViewVehicles.position, locale('loading_vehicle'), 1.0)
            goto continue
        end

        ESX.Game.Utils.DrawText3D(sellingCarTextPosition, locale('vehicle_for_sale', showingVehiclePrice), 1.0)

        ::continue::
        Citizen.Wait(sleep)
    end
end)

RegisterNetEvent('fami-sell-vehicles:viewVehicle')
AddEventHandler('fami-sell-vehicles:viewVehicle', function(data)
    if showingVehicle ~= 0 then
        if DoesEntityExist(showingVehicle) then
            DeleteEntity(showingVehicle)
        end
        showingVehicle = 0
    end

    print(data)

    local PlayerPed = ESX.PlayerData.ped
    local PlayerCoords = GetEntityCoords(PlayerPed)
    local distance = #(PlayerCoords - vector3(Config.ViewVehicles.position.x, Config.ViewVehicles.position.y, Config.ViewVehicles.position.z))
    if distance > Config.ViewVehicles.spawnDistance then
        return
    end

    showingVehicleId = data
    SpawnVehicle(showingVehicleId)
end)

function openAllVehiclesMenu()
    local elements = {}
    local vehicles = lib.callback.await('fami-sell-vehicles:getVehiclesForSale', false)
    if #vehicles == 0 then
        ESX.ShowNotification(locale('no_vehicle_for_sale'), "error")
        return
    end

    for i = 1, #vehicles do
        local model = json.decode(vehicles[i].vehicleProps).model
        table.insert(elements, {
            title = locale('choose_vehicle_item_title', GetVehicleLabel(model)),
            description = locale('choose_vehicle_item_description', vehicles[i].price),
            icon = "car",
            event = "fami-sell-vehicles:viewVehicle",
            args = vehicles[i].id,
            disabled = vehicles[i].id == showingVehicleId
        })
    end

    lib.registerContext({
        id = "fami-sell-vehicles:allVehicles",
        title = locale('choose_vehicle_title'),
        menu = "fami-sell-vehicles:vehicleOptions",
        canClose = true,
        options = elements
    })

    if lib.getOpenContextMenu() ~= nil then
        lib.hideContext(false)
    end

    lib.showContext("fami-sell-vehicles:allVehicles")
end

function GetVehicleLabel(model)
    local label = GetLabelText(GetDisplayNameFromVehicleModel(model))
    
    if label == 'NULL' then 
        label = GetDisplayNameFromVehicleModel(model)
    end

    return label
end

function formatMoney(amount)
    local formatted = amount
    while true do  
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k==0) then
            break
        end
    end
    return formatted
end

RegisterNetEvent('onResourceStop')
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        RemoveBlip(SellPointBlip)

        if point then
            point:remove()
        end

        if showPoint then
            showPoint:remove()
            if showingVehicle ~= 0 then
                if DoesEntityExist(showingVehicle) then
                    DeleteEntity(showingVehicle)
                end
                showingVehicle = 0
            end
        end
    end
end)

