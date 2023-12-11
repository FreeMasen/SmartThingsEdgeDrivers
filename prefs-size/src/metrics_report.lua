
-- update the base device init to be wrapped instead
local base_device = require "st.device"
local memtracer = require "st.memtracer"
local base_init = base_device.Device.init
local dev_meta = getmetatable(base_device.Device)
local metrics
local function wrap_dev_init()
  local wrapped, mets = memtracer.instrument_function(base_init, "device-init")
  metrics = mets
  return wrapped
end

local wrapped_dev_init = wrap_dev_init()
base_device.Device.init = wrapped_dev_init

function calculate_std_dev(samples, mean)
    local sum = 0
    local count = 0
    for _, v in pairs(samples) do
        local variance = v.memory_used_bytes - mean
        sum = sum + (variance * variance)
        count = count + 1
    end
    return math.sqrt(sum / (count - 1))
end

function calculate_median(samples)
    if not samples then
        return 0
    end
    table.sort(samples, function(lhs, rhs)
        return lhs.memory_used_bytes < rhs.memory_used_bytes
    end)
    if #samples % 2 == 0 then
        return (samples[#samples / 2].memory_used_bytes + samples[#samples / 2 + 1].memory_used_bytes) / 2
    end
    return samples[math.ceil(#samples / 2)].memory_used_bytes
end

function generate_report()
    local total = 0
    if #(metrics.samples or {}) == 0 then
        return
    end

    local min, max
    for _, sample in pairs(metrics.samples) do
        if not min then
            min = sample.memory_used_bytes
            max = sample.memory_used_bytes
        end
        min = math.min(min, sample.memory_used_bytes)
        max = math.max(max, sample.memory_used_bytes)
        total = total + sample.memory_used_bytes
    end
    local median = calculate_median(metrics.samples)
    local mean = total / #metrics.samples
    local std_dev = calculate_std_dev(metrics.samples, mean)
    return {
        name = metrics.name,
        min = min,
        max = max,
        mean = mean,
        median = median,
        std_dev = std_dev,
        count = #metrics.samples,
    }
end
local function clear()
    metrics.samples = {}
    metrics.last_sample_index = 1
end
return {
    generate_report = generate_report,
    clear = clear,
}
