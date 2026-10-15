local script_dir = arg[0]:match("^(.*[/\\])") or ""
package.path = script_dir .. "?.lua;" .. package.path

local json = require("json")
local devices = json.decode(io.read("*a")).devices

for _, runtime in ipairs(json.object_keys(devices)) do
  if runtime:find("iOS", 1, true) and runtime:find("SimRuntime", 1, true) then
    for _, device in ipairs(devices[runtime]) do
      local name = device.name or ""
      if device.isAvailable and name:find("iPhone", 1, true) then
        print(device.udid)
        return
      end
    end
  end
end

error("no available iPhone simulator")
