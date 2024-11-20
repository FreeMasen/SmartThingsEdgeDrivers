
local record capabilities
    record Command
        NAME: string
    end
    record Switch
        record Inner
            on: function():any
            off: function():any
        end
        record Commands
            on: Command
            off: Command
        end
        switch: Inner
        ID: string
        commands: Commands
    end
    record DoorControl
        record Inner
            open: function():any
            opening: function():any
            closed: function():any
            closing: function():any
            unknown: function():any
        end
        record Commands
            close: Command
            open: Command
        end
        doorControl: Inner
        ID: string
        commands: Commands
    end
    switch: Switch
    doorControl: DoorControl
end

return capabilities
