

local function css()
  return [[
:root {
    /*Grey-100*/
    --light-grey: #EEEEEE;
    /*Grey-600*/
    --grey: #757575;
    /*Grey-900*/
    --dark-grey: #1F1F1F;
    /*Blue-500*/
    --blue: #0790ED;
    /*Teal-500*/
    --teal: #00B3E3;
    /*Red-500*/
    --red: #FF4337;
    /*Yellow-500*/
    --yellow: #FFB546;
    /*Green-500*/
    --green: #3DC270;
}

html,
body {
    padding: 0;
    margin: 0;
    border: 0;
}

* {
    font-family: sans-serif;
}

button {
    margin-top: 10px;
    height: 30px;
    line-height: 30px;
    text-align: center;
    padding: 0 5px;
    cursor: pointer;
    background-color: var(--blue);
    color: #fff;
    border: 0;
    font-size: 13pt;
    border-radius: 8px;

}

header {
    text-align: center;
    width: 100%;
    color: #fff;
    background-color: var(--blue);
    margin: 0 0 8px 0;
    padding: 10px 0;
}

body.error header,
body.error button,
body.error .title {
    background-color: var(--red) !important;
    color: var(--dark-grey) !important;
}

body.error .device {
    border-color: var(--red);
}

header>h1 {
    margin: 0;
}

h2 {
    text-align: center;
    margin: 0;
}

#new-button-container {
    margin: auto;
    width: 250px;
    display: flex;
}

#new-button-container>button {
    width: 200px;
    margin: auto;
    height: 50px;
}

#button-list-container {
    display: flex;
    flex-flow: row wrap;
    align-items: center;
    margin: auto;
    justify-content: space-between;
    max-width: 800px;
}

.device {
    display: flex;
    flex-flow: column;
    width: 175px;
    border: 1px solid var(--blue);
    border-radius: 5px;
    padding: 2px;
    margin-top: 5px;
}

.device .title {
    font-size: 15pt;
    background: var(--blue);
    width: 100%;
    text-align: center;
    color: var(--light-grey);
    padding-top: 5px;
    border-radius: 4px;
}

.device.sensor .color-temp {
    display: none;
}

.device .states {
    display: flex;
    flex-flow: column;
    align-content: start;
    align-items: start;
}

#event-history {
    margin: 10px auto 0;
    border-radius: 5px;
}

th {
    background: var(--blue);
    color: white;
    padding: 5px;

}

th+th {
    border-left: 1px solid white;
}

table,
tr,
td {
    border: 1px solid var(--blue);
    border-collapse: collapse;
}
  ]]
end

local function js()
  return [[
const BUTTON_LIST_ID = 'button-list-container';
const NEW_BUTTON_ID = 'new-button';
/**
 * @type HTMLTemplateElement
 */
const DEVICE_TEMPLATE = document.getElementById("device-template");
let known_buttons = [];

let PROP = Object.freeze({
    SWITCH: "switch",
});

let state_update_timers = {

}

Promise.sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function create_device() {
    let result = await make_request('/newdevice', 'POST');
    if (result.error) {
        return console.error(result.error, result.body);
    }

    let list;
    let err_ct = 0;
    while (true) {
        try {
            list = await get_all_devices();
        } catch (e) {
            console.error('error fetching buttons', e);
            err_ct += 1;
            if (err_ct > 5) {
                break;
            }
            await Promise.sleep(1000);
            continue;
        }
        if (list.length !== known_buttons.length) {
            break;
        }
    }
    clear_button_list();
    for (const info of list) {
        append_new_device(info);
    }
}

function append_new_device(info) {
    let list = document.getElementById(BUTTON_LIST_ID);
    let element = DEVICE_TEMPLATE.content.cloneNode(true);
    let container = element.querySelector(".device");
    container.id = info.device_id;
    update_device_card(container, info, true)
    list.appendChild(container);
}

function handle_single_update(info) {
    console.log("handle_single_update", info);
    let element = document.getElementById(info.device_id);
    append_to_history(
        info.device_name || info.device_id || "???",
        info.event || "unknown",
        info?.state?.switch || "",
        info?.state?.interval || "",
        info?.state?.timeout || "",
        info?.state?.last_duration?.toFixed(3) || ""
    )
    switch (info.event) {
        case "init":
        case "update": {
            if (!element) {
                return append_new_device(info);
            }
            update_device_card(element, info);
            break;
        }
        case "removed": {
            if (!!element) {
                element.parentElement.removeChild(element);
            }
            append_to_history(info.device_id, "removed", "", "", "", "")
            break;
        }
        default:
            append_to_history(info.device_name || info.device_id || "??", info.event || "unknown", "", "", "", "")
            break;
    }
}

function update_device_card(element, info, register_handlers) {
    console.log("update_device_card", info);
    let title = element.querySelector(".title");
    title.innerText = info.device_name
    let switch_on = info.state.switch === "on";
    
    let switch_state_on = element.querySelector('.switch-on');
    let switch_state_off = element.querySelector('.switch-off');
    switch_state_on.checked = switch_on;
    switch_state_off.checked = !switch_on;
    switch_state_on.name = `${info.device_id}-switch-state`
    switch_state_off.name = `${info.device_id}-switch-state`

    let switch_level = element.querySelector(".switch-level");

    if (register_handlers) {
        switch_state_on.parentElement.addEventListener("click", () => handle_change(info.device_id, PROP.SWITCH));
        switch_state_off.parentElement.addEventListener("click", () => handle_change(info.device_id, PROP.SWITCH));
    }
}

/**
 * Get the binary value form a form element
 * @param {HTMLDivElement} div element to search
 * @param {string} selector arg to query selector
 * @param {string} is_checked Value returned if checked
 * @param {string} other value returned if not checked
 * @returns string
 */
function get_binary_value(div, selector, is_checked, other) {
    let ele = div.querySelector(selector)?.checked || false;
    return ele ? is_checked : other
}


function get_float_value(div, selector) {
    let input = div.querySelector(selector);
    if (!input) {
        console.warn("div didn't contain", selector)
        return 0
    }
    let value_str = input.value || "0";
    try {
        return parseFloat(value_str);
    } catch (e) {
        console.warn("invalid float value", e);
        return 0;
    }
}

/**
 * 
 * @param {string} device_id 
 * @param {string} prop The property that changed
 */
function handle_change(device_id, prop) {
    let existing_timer = state_update_timers[device_id];
    let props = [prop]
    if (!!existing_timer) {
        clearTimeout(existing_timer.timer);
        props.push(...existing_timer.props);
        existing_timer[device_id] = null;
    }
    let timer = setTimeout(() => send_state_update(device_id, props), 300);
    state_update_timers[device_id] = {
        timer,
        props,
    };
}

/**
 * 
 * @param {string} device_id
 * @param {string[]} properties 
 */
async function send_state_update(device_id, properties) {
    let state = serialize_device(device_id, properties);
    let resp = await make_request("/device_state", "PUT", {
        device_id,
        state,
    });
    if (resp.error) {
        console.error("Error making request", resp.error, resp.body);
    }
}


async function make_request(url, method = 'GET', body = undefined) {
    console.log('make_request', url, method, body);
    let opts = {
        method,
        body,
    }
    if (typeof body == 'object') {
        opts.body = JSON.stringify(body);
        opts.headers = {
            ['Content-Type']: 'application/json',
        }
    }
    let res = await fetch(url, opts);
    if (res.status !== 200) {
        return {
            error: res.statusText,
            body: await res.text()
        };
    }
    return {
        body: await res.json()
    };
}

function clear_button_list() {
    let list = document.getElementById(BUTTON_LIST_ID);
    while (list.hasChildNodes()) {
        list.removeChild(list.lastChild);
    }
}

async function get_all_devices() {
    let result = await make_request('/info');
    if (result.error) {
        console.error(result.body);
        throw new Error(result.error)
    }
    return result.body;
}

function serialize_device(device_id, properties) {
    let device_card = document.getElementById(device_id);
    return serialize_device_card(device_card, properties)
}

function serialize_device_card(device_card, properties) {
    let props = properties || ["switch"];
    let state = {}
    for (let prop of props) {
        switch (prop) {
            case "switch": {
                state["switch"] = get_binary_value(device_card, ".switch-on", "on", "off");
                break;
            }
            default:
                console.error("Invalid prop, skipping", prop)
        }
    }
    return state
}

function serialize_devices() {
    return Array.from(document.querySelectorAll(".device")).map(ele => serialize_device_card(ele))
}

async function put_into_datastore(key, value) {
    await make_request(`/set-in-store/${key}`, "PUT", value || { when: new Date().toISOString(), where: location.toString(), data: serialize_devices() });
    return (await make_request("/store-size")).body.size
}

function append_to_history(
    device_name, event_type, switch_state, interval, timeout, last_measurement
) {
    let dest = document.getElementById("event-history-body");
    let row = document.getElementById("history-entry-template").content.cloneNode(true);
    let args = [
        [".when", (new Date()).toISOString()],
        [".device-name", device_name],
        [".event-type", event_type],
        [".switch-state", switch_state],
        [".interval", interval],
        [".interval", interval],
        [".timeout", timeout],
        [".last-measurement", last_measurement],
    ]
    for (let [selector, value] of args) {
        set_element_content_by_selector(row, selector, value)
    }
    dest.appendChild(row);
}

function set_element_content_by_selector(ele, selector, value) {
    let target = ele.querySelector(selector);
    target.innerText = value.toString();
}

(() => {
    get_all_devices().then(list => {
        known_buttons = list;
        for (const info of list) {
            append_new_device(info);
        }
    }).catch(console.error);
    let new_btn = document.getElementById(NEW_BUTTON_ID);
    new_btn.addEventListener('click', create_device);
    let sse = new EventSource("/subscribe");
    sse.addEventListener("message", ev => {
        let info = JSON.parse(ev.data);
        handle_single_update(info);
    });
    sse.addEventListener("open", ev => {
        console.log("sse opened!")
        sse.addEventListener("error", e => {
            console.error(`Error from sse`, e);
            sse.close()
            document.body.classList.add("error");
            let header = document.querySelector("header h1")[0];
            header.firstElementChild.innerText += " URL Expired"
        });
    })
})();
  ]]
end

local function html()
  return [[
<!DOCTYPE html>
<html>

<head>
    <meta content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes" name="viewport">
    <meta charset="utf-8">
    <title>Timer</title>
    <link rel="stylesheet" type="text/css" href="/style.css" />
</head>

<body>
    <header>
        <h1 style="text-align:center">Timer</h1>
    </header>
    <div id="new-button-container">
        <button id="new-button">Add Device</button>
    </div>
    <h2>
        Timers
    </h2>
    <div id="button-list-container">

    </div>
    <h2>
        History
    </h2>
    <table id="event-history">
        <thead>

            <tr>
                <th>
                    When
                </th>
                <th>
                    Device
                </th>
                <th>
                    Event Type
                </th>
                <th>
                    Switch State
                </th>
                <th>
                    Interval
                </th>
                <th>
                    Timeout
                </th>
                <th>
                    Last Measurement
                </th>
            </tr>
        </thead>
        <tbody id="event-history-body">
        </tbody>
    </table>

    <template id="device-template">
        <div class="device">
            <span class="title"></span>
            <div class="states">
                <div class="switch-state">
                    <span class="sensor-name">Switch</span>
                    <div class="switch-info">
                        <div class="radio-group">
                            <label>
                                On
                                <input type="radio" name="switch-state" class="switch-on" value="on">
                            </label>
                            <label>
                                Off
                                <input type="radio" name="switch-state" class="switch-off" value="off">
                            </label>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </template>
    <template id="history-entry-template">
        <tr class="history-entry">
            <td class="when"></td>
            <td class="device-name"></td>
            <td class="event-type"></td>
            <td class="switch-state"></td>
            <td class="interval"></td>
            <td class="timeout"></td>
            <td class="last-measurement"></td>
        </tr>
    </template>
    <script type="text/javascript" src="/index.js">
    </script>
</body>

</html>
  ]]
end

return {
  css = css,
  js = js,
  html = html,
}
