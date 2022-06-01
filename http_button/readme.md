# HTTP Button

This driver emulates a button device by listening for http POST requests on the hub.

To interact with the driver you simply need to `curl` the correct ip and port combination.

## Getting started

### Adding your first device

After installing this driver to your hub, you will need to add the first device from OneApp.
To do so, you will select the + button that appears in the top right of the main user interface.
This will bring you to a list of things you could add to a location, from this list select the
"Device" option. This will bring you to a list of possible device types you could add, instead
of selecting one of those, there is a button on this screen that says "Scan Nearby" (On iOS this
is in the bottom right, on Android, it is in the top right). This will start running your newly
installed `http_button` driver which will discover a single device.

## Getting the port

The driver isn't allowed to request a port when opening a socket this means the port will
change each time this driver is started. To determine what port you need to interact with,
start the live logs from smartthings CLI and a log message coming from `http_button` will
pop up every 5 seconds with the ip and port number in them.

```sh
smartthings edge:drivers:logcat --hub-address=<hub-ip>
┌───┬──────────────────────────────────────┬─────────────┐
│   | Driver Id                            │ Name        │
├───┼──────────────────────────────────────┼─────────────┤
│ 1 │ b2ddeeba-a895-4457-9584-bb23a990cb78 │ http_button │
└───┴──────────────────────────────────────┴─────────────┘
? Select a driver. (all) 1
connecting... connected
2022-06-01T19:36:12.784002782+00:00 INFO http_button  listening on http://192.168.1.6:35983
```

Alternatively, if you are planning on interacting with this driver programmatically, you can
send a UDP broadcast message to the ip 239.255.255.250 on port 9887. In Lua that might look
like this

```lua
local cosock = require "cosock"

local function find_url()
    local ip = '239.255.255.250'
    local port = 9887
    local sock = cosock.socket.udp()
    assert(sock:setsockname(ip, port))
    -- Ensure we can reuse our port number
    assert(sock:setoption('reuseaddr', true))
    -- Add ourselves to the broadcast group
    assert(sock:setoption('ip-add-membership', {multiaddr = ip, interface = '0.0.0.0'}))
    -- Ignore the messages we send ourselves
    assert(sock:setoption('ip-multicast-loop', false))
    -- Don't wait longer than 5 seconds for a reply
    sock:settimeout(5)
    while true do
        -- Send the query to the broadcast group
        sock:sendto("whereareyou", ip, port)
        print("sent whereareyou")
        while true do
            -- Listen for a reply from the group
            url, ip_or_err, _port = sock:receivefrom()
            
            print("received", url, ip_or_err, _port)
            if url and url:match("^http://") then
                return url
            else
                print("Error: ", url, ip_or_err, _port)
                break
            end
        end
    end
end

cosock.spawn(find_url)
cosock.run()

```

## Interacting with the driver

Once you have your IP/port number, you can use `curl` or `wget` or `postman` to trigger
button presses. The following examples will be using `curl` but the basic idea is
that you need to send an HTTP POST requests to the IP and port you captured above
followed by the device id or special endpoint.

An alternative is to head to `http://<hub-ip>:port/index.html` in your browser for GUI interactions.

### Examples

These will assume an IP address of `192.168.0.199` and a port of `54345`.

#### Get the device ids

```sh
$ curl -X GET http://192.168.0.199:54345/info
[{"device_id": "aaaaaaaa-bbbb-cccc-dddd-ffffffffffff", "device_name": "button 0"}
{"device_id": "11111111-2222-3333-4444-555555555555", "device_name": "button 1"}]
```

This would indicate that there are 2 buttons we can interact with.

#### Triggering a push event

```sh
$ curl -X POST http://192.168.0.199:54345/action \
-d "{\"device_id\": \"aaaaaaaa-bbbb-cccc-dddd-ffffffffffff\", \"action\": \"push\" }"
```

#### Triggering a held event

```sh
$ curl -X POST http://192.168.0.199:54345/action \
-d "{\"device_id\": \"aaaaaaaa-bbbb-cccc-dddd-ffffffffffff\", \"action\": \"hold\" }"
```

#### Adding Devices

[The first device you add to this _has_ to come through via OneApp.](#getting-started)

After the first button, the driver will do nothing when you "Scan Nearby" instead you will want
to use the `/newdevice` endpoint

```sh
curl -X POST http://192.168.0.199:54345/newdevice
{"device_id": "baaaaaaa-bbbb-cccc-dddd-ffffffffffff", "device_name": "Button 2"}
```

#### Updating Devices

> This might not actually work very well ATM

Once you have a few devices installed, if you wanted to change their label, you can do so with the following.

```sh
curl -X POST http://192.168.0.199:54345/newlabel \
-d "{\"device_id\": \"aaaaaaaa-bbbb-cccc-dddd-ffffffffffff\", \"name\": \"Party Button!!!\" }""
```

#### Quieting the ping message

At startup, the driver will start sending a log message with the current IP address and the port
that was provided by the hub every 5 seconds. To stop this message you can send a request to `/quiet`

```sh
curl -X POST http://192.168.0.199:54345/quiet
Stopped ping loop
```

#### Checking if the server is running

It may be nice to just check if the server is running, to do this the `/health` endpoint exists for
that. Any request to this will either return `1` if the server is up or fail if the
server is down

```sh
curl http://192.168.0.199:54345/health
1
```
