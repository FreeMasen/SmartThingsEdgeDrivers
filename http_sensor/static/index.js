const BUTTON_LIST_ID = 'button-list-container';
const NEW_BUTTON_ID = 'new-button';
/**
 * @type HTMLTemplateElement
 */
const DEVICE_TEMPLATE = document.getElementById("device-template");
let known_buttons = [];


let PROP = Object.freeze({
    CONTACT: "contact",
    TEMP: "temp",
    AIR: "air",
    SWITCH: "switch",
    LEVEL: "level",
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
