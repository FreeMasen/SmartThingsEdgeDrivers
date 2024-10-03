

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

.device.extended .title {
    background-color: var(--green);
}

.device.extended .color-temp {
    display: unset;
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

.contact-state {
    width: 100%;
}

.sensor-name {
    font-weight: bold;
    margin-top: 5px;
    display: inline-block;
}

.contact-state .radio-group {
    display: flex;
    flex-flow: row;
    align-items: start;
    justify-content: space-between;
}

.temp-state {
    width: 100%;
    flex-flow: column;
    display: flex;
    justify-content: space-between;
}

.temp-info {
    display: flex;
    flex-flow: row;
    width: 100%;
    justify-content: space-between;
}

.temp-input-container input {
    width: 50px;
}

.temp-info .radio-group {
    width: 75px;
    display: flex;
    flex-flow: row;

}

.air-state input {
    width: 50px;
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
const SENSOR_CLASS = "sensor";
const EXTEND_CLASS = "extended";
const PROFILE_CLASS_MAP = Object.freeze({
    ["http_sensor.v1"]: SENSOR_CLASS,
    ["http_sensor2.v1"]: SENSOR_CLASS,
    ["http_sensor-ext.v1"]: EXTEND_CLASS,
    ["http_sensor-ext2.v1"]: EXTEND_CLASS,
})
const NOT_CLASS_MAP = Object.freeze({
    [SENSOR_CLASS]: EXTEND_CLASS,
    [EXTEND_CLASS]: SENSOR_CLASS,
})

let PROP = Object.freeze({
    CONTACT: "contact",
    TEMP: "temp",
    AIR: "air",
    SWITCH: "switch",
    LEVEL: "level",
    COLOR_TEMP: "colorTemp",
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
            break;
        }
        case "profile": {
            let new_class = PROFILE_CLASS_MAP[info.profile]
            let old_class = NOT_CLASS_MAP[new_class];
            element.classList.add(new_class)
            element.classList.remove(old_class);
            update_device_card(element, info);
        }
    }
}

function update_device_card(element, info, register_handlers) {
    console.log("update_device_card", info);
    let device_id = info.device_id;
    let title_span = element.querySelector(".title");
    title_span.innerText = info.device_name;
    /** @type HTMLInputElement */
    let contact_open = element.querySelector('.contact-open');
    let contact_closed = element.querySelector('.contact-closed');
    let is_open = info.state.contact === "open";
    contact_open.checked = is_open;
    contact_closed.checked = !is_open;
    contact_open.name = `${device_id}-contact`
    contact_closed.name = `${device_id}-contact`
    
    
    /** @type HTMLInputElement */
    let temp_value = element.querySelector('.temp-value');
    temp_value.value = info.state.temp.value;
    
    let temp_c = element.querySelector('.temp-c');
    let temp_f = element.querySelector('.temp-f');
    temp_c.name = `${device_id}-temp-unit`
    temp_f.name = `${device_id}-temp-unit`
    let is_f = info.state.temp.unit === 'F';
    temp_c.checked = !is_f;
    temp_f.checked = is_f;
    
    let air_value = element.querySelector('.air-value')
    air_value.value = info.state.air;

    let switch_on = info.state.switch === "on";
    
    let switch_state_on = element.querySelector('.switch-on');
    let switch_state_off = element.querySelector('.switch-off');
    switch_state_on.checked = switch_on;
    switch_state_off.checked = !switch_on;
    switch_state_on.name = `${device_id}-switch-state`
    switch_state_off.name = `${device_id}-switch-state`

    let switch_level = element.querySelector(".switch-level");
    switch_level.value = info.state.switch_level;

    let current_class = PROFILE_CLASS_MAP[info.profile] ?? SENSOR_CLASS;
    let stale_class = NOT_CLASS_MAP[current_class] ?? EXTEND_CLASS;
    element.classList.add(current_class);
    element.classList.remove(stale_class);

    if (current_class == EXTEND_CLASS) {
        let color_temp = element.querySelector(".color-temp-value");
        color_temp.value = info.state.color_temp;
        if (register_handlers) {
            color_temp.addEventListener("change", () => handle_change(device_id, PROP.COLOR_TEMP))
        }
    }


    if (register_handlers) {
        temp_value.addEventListener("change", () => handle_change(device_id, PROP.TEMP));
        temp_c.addEventListener("change", () => handle_change(device_id, PROP.TEMP));
        air_value.addEventListener("change", () => handle_change(device_id, PROP.AIR));
        contact_open.parentElement.addEventListener("click", () => handle_change(device_id, PROP.CONTACT));
        contact_closed.parentElement.addEventListener("click", () => handle_change(device_id, PROP.CONTACT));
        switch_state_on.parentElement.addEventListener("click", () => handle_change(device_id, PROP.SWITCH));
        switch_state_off.parentElement.addEventListener("click", () => handle_change(device_id, PROP.SWITCH));
        switch_level.addEventListener("change", () => handle_change(device_id, PROP.LEVEL));
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
    let device_card = document.getElementById(device_id);
    let props = properties || ["contact", "temp", "air", "switch", "level"];
    let state = {}
    for (let prop of props) {
        switch (prop) {
            case "contact": {
                state.contact = get_binary_value(device_card, ".contact-open", "open", "closed");
                break;
            }
            case "temp": {
                state.temp = {
                    value: get_float_value(device_card, ".temp-value"),
                    unit: get_binary_value(device_card, ".temp-f", "F", "C"),
                };
                break;
            }
            case "air": {
                state.air = get_float_value(device_card, ".air-value");
                break;
            }
            case "switch": {
                state["switch"] = get_binary_value(device_card, ".switch-on", "on", "off");
                break;
            }
            case "level": {
                state.level = get_float_value(device_card, ".switch-level");
                break;
            }
            default:
                console.error("Invalid prop, skipping", prop)
        }
    }
    let resp = await make_request("/device_state", "PUT", {
        device_id,
        state,
    });
    if (resp.error) {
        console.error("Error making request", resp.error, resp.body);
    }
}

/**
 * 
 * @param {string} device_id 
 * @param {string} profile
 */
async function send_profile_update(device_id, profile) {
    return await make_request("/profile", "PUT", {
        device_id,
        profile,
    })
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
    <title>HTTP Sensor</title>
    <link rel="stylesheet" type="text/css" href="/style.css" />
</head>

<body>
    <header>
        <h1 style="text-align:center">HTTP Sensor</h1>
    </header>
    <div id="new-button-container">
        <button id="new-button">Add Device</button>
    </div>
    <div id="button-list-container">

    </div>

    <template id="device-template">
        <div class="device">
            <span class="title"></span>
            <div class="states">
                <div class="contact-state">
                    <span class="sensor-name">Contact</span>
                    <div class="radio-group">
                        <label class="open-control">
                            Open
                            <input value="open" type="radio" class="contact-open" name="contact" />
                        </label>
                        <label class="closed-control">
                            Closed
                            <input value="closed" type="radio" class="contact-closed" name="contact" />
                        </label>
                    </div>
                </div>
                <div class="temp-state">
                    <span class="sensor-name">Temp.</span>
                    <div class="temp-info">
                        <label for="temp-value" class="temp-input-container">
                            <input type="number" name="temp-value" class="temp-value" />
                        </label>
                        <div class="radio-group">
                            <label>
                                C
                                <input type="radio" class="temp-c" name="temp-unit" />
                            </label>
                            <label>
                                F
                                <input type="radio" class="temp-f" name="temp-unit" />
                            </label>
                        </div>
                    </div>
                </div>
                <div class="air-state">
                    <span class="sensor-name">Air Q.</span>
                    <div class="air-info">
                        <label for="air-value">
                            <input type="number" name="air-value" class="air-value" />
                        </label>
                        <span>CAQI</span>
                    </div>
                </div>
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
                        <label>
                            Level
                            <input type="range" min="0" max="100" class="switch-level" />
                        </label>
                    </div>
                </div>
                <div class="color-temp">
                    <span class="sensor-name">Color Temp</span>
                    <div class="color-info">
                        <label>
                            Level
                            <input type="range" min="0" max="3000" class="color-temp-value" />
                        </label>
                    </div>
                </div>
            </div>
        </div>
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
