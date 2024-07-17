

function css()
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

.button-container {
    display: flex;
    flex-flow: column;
    justify-content: space-between;
    align-items: center;
    border: 1px solid var(--blue);
    margin-top: 10px;
    border: 1px solid var(--blue);
    padding: 5px;
    border-radius: 5px;
    margin-top: 5px;
    position: relative;
}

.device {
    display: flex;
    flex-flow: column;
    width: 175px;
    border: 1px solid var(--blue);
    border-radius: 5px;
    padding: 2px;
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

function js()
  return [[
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
  ]]
end

function html()
  return [[
<!DOCTYPE html>
<html>

<head>
    <meta content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes" name="viewport">
    <meta charset="utf-8">
    <title>HTTP Sensor</title>
    <link rel="stylesheet" type="text/css" href="/index.css" />
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
