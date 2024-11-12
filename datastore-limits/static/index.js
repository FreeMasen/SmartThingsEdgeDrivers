const BUTTON_LIST_ID = 'button-list-container';
const NEW_BUTTON_ID = 'new-button';
const ALL_ON_ID = 'toggle-all-on';
const ALL_OFF_ID = 'toggle-all-off';
/**
 * @type HTMLTemplateElement
 */
const DEVICE_TEMPLATE = document.getElementById("device-template");
const DATASTORE_SIZE = document.getElementById("datastore-size");
const DATASTORE_CONTAINER = document.getElementById("datastore-container");
let PROP = Object.freeze({
    SWITCH: "switch",
});

let known_devices = [];
let state_update_timers = {}

let last_updatd_datastore = new Date(0);

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
        if (list.length !== known_devices.length) {
            break;
        }
    }
    clear_device_list();
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
        case "added":
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
    }
    update_datastore();
}

function update_device_card(element, info, register_handlers) {
    console.log("update_device_card", info);
    let device_id = info.device_id;
    let title_span = element.querySelector(".title");
    title_span.innerText = info.device_name;

    let switch_on = info.state.switch === "on";
    
    let switch_state_on = element.querySelector('.switch-on');
    let switch_state_off = element.querySelector('.switch-off');
    switch_state_on.checked = switch_on;
    switch_state_off.checked = !switch_on;
    switch_state_on.name = `${device_id}-switch-state`
    switch_state_off.name = `${device_id}-switch-state`


    if (register_handlers) {
        switch_state_on.parentElement.addEventListener("click", () => handle_change(device_id, PROP.SWITCH));
        switch_state_off.parentElement.addEventListener("click", () => handle_change(device_id, PROP.SWITCH));
        let clear_button = element.querySelector(".clear-button")
        if (!!clear_button) {
            clear_button.addEventListener("click", () => clear_datastore(device_id))
        }
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

function clear_device_list() {
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

function update_timestamp_keys(obj) {
    for (let k of Object.getOwnPropertyNames(obj)) {
        let val = obj[k]
        try {
            let key_int = Number.parseFloat(k);
            if (Number.isNaN(key_int)) {
                continue;
            }
            let key_dt = new Date(key_int * 1000);
            if (Number.isNaN(key_dt)) {
                continue;
            }
            let new_key = key_dt.toISOString();
            obj[new_key] = val;
            delete obj[k];
        } catch { }
    }
}
/**
 * Recursively update the log table keys from unix timestamps into ISO datetime strings
 * @param {object} ds The object to transform
 */
function transform_datastore(ds) {
    if (typeof ds !== "object") {
        return
    }
    for (let k of Object.getOwnPropertyNames(ds)) {
        let prop = ds[k];
        if (k === "activity_log" || k == "driver_log") {
            update_timestamp_keys(prop)
        } else {
            transform_datastore(prop);
        }
    }
}

async function clear_datastore(device_id) {
    await make_request("/datastore", "DELETE", {
        device_id,
    });
    let ds = await get_datastore()
    if (!!ds) {
        handle_datastore_update(ds.datastore, ds.size)
    }
}

function format_size(size) {
    if (typeof size != "number") {
        return
    }
    let unit = "b";
    let units = ["kb", "mb", "gb"]
    while (size > 1024 && units.length > 0) {
        unit = units.shift();
        size /= 1024;
    }
    return `${size.toFixed(3)} ${unit}`;
}

async function get_datastore() {
    let ds = await make_request("/datastore");
    if (ds.error) {
        return console.error("Error requesting datastore", ds.error, ds.body)
    }
    let size = JSON.stringify(ds.body).length;
    transform_datastore(ds.body);
    return {
        datastore: ds.body,
        size,
    };
}

function render_datastore(contents) {
    let was_hidden = false;
    while (DATASTORE_CONTAINER.hasChildNodes()) {
        was_hidden = DATASTORE_CONTAINER.lastChild.classList.contains("hidden");
        DATASTORE_CONTAINER.removeChild(DATASTORE_CONTAINER.lastChild);
    }
    let serd = JSON.stringify(contents, undefined, 4);
    let pre = document.createElement("pre");
    if (was_hidden) {
        pre.classList.add("hidden");
    }
    pre.innerHTML = serd;
    DATASTORE_CONTAINER.appendChild(pre);
}

function handle_datastore_update(datastore, size) {
    render_datastore(datastore)
    DATASTORE_SIZE.innerText = format_size(size)
}

async function update_datastore() {
    let now = new Date();
    let diff = now - last_updatd_datastore;
    if (diff < 15000) {
        return;
    }
    last_updatd_datastore = now;
    try {
        let ds = await get_datastore()
        if (!!ds) {
            handle_datastore_update(ds.datastore, ds.size)
            last_updatd_datastore = new Date();
        }
    } catch (e) {
        console.warn("error getting datastore:", e)
    }
}

async function datastore_poll() {
    while (!document.body.classList.contains("error")) {
        await update_datastore();
        await Promise.sleep(15000);
    }
}

function toggle_all_states(new_state) {
    for (let ele of Array.from(document.querySelectorAll(".device"))) {
        let radio
        if (new_state == "on") {
            radio = ele.querySelector(".switch-on");
        } else {
            radio = ele.querySelector(".switch-off");
        }
        radio.click();
    }
}

let looping = false;
async function start_toggle_loop() {
    looping = true;
    let is_on = true;
    while (looping) {
        toggle_all_states(is_on ? "on" : "off");
        is_on = !is_on;
        await Promise.sleep(15000);
    }
}

function stop_toggle_loop() {
    looping = false;
}

function toggle_display_datastore() {
    let ds_cont = document.getElementById("datastore-container");
    let btn = document.getElementById("datastore-toggle");
    if (!ds_cont.firstChild) {
        return;
    }
    /**
     * @type HTMLPreElement
     */
    const pre_ele = ds_cont.firstChild;
    if (pre_ele.classList.contains("hidden")) {
        btn.innerText = "Hide Datastore";
        pre_ele.classList.remove("hidden");
    } else {
        btn.innerText = "Show Datastore";
        pre_ele.classList.add("hidden");
    }
}

function setup_buttons() {
    let new_btn = document.getElementById(NEW_BUTTON_ID);
    new_btn.addEventListener('click', create_device);
    let all_on_btn = document.getElementById(ALL_ON_ID);
    all_on_btn.addEventListener("click", () => toggle_all_states("on"));
    let all_off_btn = document.getElementById(ALL_OFF_ID);
    all_off_btn.addEventListener("click", () => toggle_all_states("off"));
}

async function put_in_store(obj) {
    return await make_request(`/datastore/${(new Date()).toISOString()}`, "PUT", obj || {})
}

(() => {
    get_all_devices().then(list => {
        known_devices = list;
        for (const info of list) {
            append_new_device(info);
        }
    }).catch(console.error);
    setup_buttons();
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
            let header = document.getElementById("page-header");
            header.innerText += " URL Expired"
        });
    });
    datastore_poll();
})();
