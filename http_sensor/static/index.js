const BUTTON_LIST_ID = 'button-list-container';
const NEW_BUTTON_ID = 'new-button';
/**
 * @type HTMLTemplateElement
 */
const DEVICE_TEMPLATE = document.getElementById("device-template");
let known_buttons = [];

let state_update_timers = {

}

Promise.sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function create_button() {
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
        append_new_button(info);
    }
}

function append_new_button(info) {
    let list = document.getElementById(BUTTON_LIST_ID);

    let clone = DEVICE_TEMPLATE.content.cloneNode(true);
    let device_id = info.device_id;
    let container = clone.querySelector(".device");
    container.id = device_id;
    let title_span = clone.querySelector(".title");
    title_span.innerText = info.device_name;
    /** @type HTMLInputElement */
    let contact_open = clone.querySelector('.contact-open');
    let contact_closed = clone.querySelector('.contact-closed');
    let is_open = info.state.contact === "open";
    contact_open.checked = is_open;
    contact_closed.checked = !is_open;
    contact_open.parentElement.addEventListener("click", () => handle_change(device_id));
    contact_closed.parentElement.addEventListener("click", () => handle_change(device_id));
    
    /** @type HTMLInputElement */
    let temp_value = clone.querySelector('.temp-value');
    temp_value.value = info.state.temp.value;
    temp_value.addEventListener("change", () => handle_change(device_id));
    let temp_c = clone.querySelector('.temp-c');
    let temp_f = clone.querySelector('.temp-f');
    let is_f = info.state.temp.unit === 'F';
    temp_c.checked = !is_f;
    temp_f.checked = is_f;
    temp_c.addEventListener("change", () => handle_change(device_id));
    
    let air_value = clone.querySelector('.air-value')
    air_value.value = info.state.air;
    air_value.addEventListener("change", () => handle_change(device_id));


    list.appendChild(clone);
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
 */
function handle_change(device_id) {
    if (!!state_update_timers[device_id]) {
        clearTimeout(state_update_timers[device_id]);
    }
    state_update_timers[device_id] = setTimeout(() => {
        send_state_update(device_id);
    }, 300);
}

/**
 * 
 * @param {string} device_id 
 */
async function send_state_update(device_id) {
    let device_card = document.getElementById(device_id);
    let contact = get_binary_value(device_card, ".contact-open", "Open", "Closed");
    let temp_value = get_float_value(device_card, ".temp-value");
    let temp_unit = get_binary_value(device_card, ".temp-f", "F", "C");
    let air = get_float_value(device_card, ".air-value");
    let resp = await make_request("/device_state", "PUT", {
        device_id,
        state: {
            contact,
            temp: {
                value: temp_value,
                unit: temp_unit,
            },
            air,
        }
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
            append_new_button(info);
        }
    }).catch(console.error);
    let new_btn = document.getElementById(NEW_BUTTON_ID);
    new_btn.addEventListener('click', create_button);
})();
