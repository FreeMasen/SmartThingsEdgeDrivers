
local record DeviceMetadata
    type: string
    device_network_id: string
    label: string
    profile: string
    parent_device_id: string|nil
    manufacturer: string|nil
    model: string|nil
    vendor_provided_label: string|nil
end

local type CapabilityHandlers = {string: {string: function(Driver, Driver.Device)}}

local record LifeCycleHandlers
    init: function(Driver, Driver.Device)
    added: function(Driver, Driver.Device)
    infoChanged: function(Driver, Driver.Device)
end

local record DriverLifecycleHandlers
    shutdown: function(Driver)
end

local record DriverTemplate
    discovery: function(driver: Driver, opts: table , should_continue: function():boolean)
    lifecycle_handlers: LifeCycleHandlers
    capability_handlers: CapabilityHandlers
    driver_lifecycle: DriverLifecycleHandlers
end

local record Driver
    record Device
        record DriverMetadata
            id: string
            name: string
            type: string
        end
        device_id: string
        deviceNetworkId: string
        driver: DriverMetadata
        components: any
        emit_event: function(Device, any)
        set_field: function(string, any, table)
        get_field: function(string): any
        get_latest_state: function(string, string, string, any, any): any|nil
    end
    metamethod __call: function(any, name: string, tempalte: DriverTemplate): Driver
    get_devices: function(Driver): {Device}
    try_create_device: function(Driver, DeviceMetadata)
    init: function(name: string, template: DriverTemplate): Driver
    run: function(Driver)
end

return Driver
