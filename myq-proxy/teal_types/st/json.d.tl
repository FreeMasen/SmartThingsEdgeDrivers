

local record json
    encode: function<T>(value: T): string
    decode: function<T>(encoded: string): T
end

return json
