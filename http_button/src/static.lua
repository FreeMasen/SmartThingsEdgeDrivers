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

header > h1 {
    margin: 0;
}

#new-button-container {
    margin: auto;
    width: 250px;
    display: flex;
}

#new-button-container > button {
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
.button-title {
    font-size: 15pt;
    background: var(--blue);
    width: 100%;
    text-align: center;
    color: var(--light-grey);
    padding: 5px;
    margin-top: 0;
}
.button-group {
    display: flex;
    flex-flow: row;
    justify-content: space-around;
    align-content: center;
    width: 100%;
}
.button-action {
    font-size: 12pt;
    width: 100px;
    height: 60px;
    margin-right: 5px;
    margin-left: 5px;
}
    ]]
end

local function js()
    return [[
        const BUTTON_LIST_ID = 'button-list-container';
        const NEW_BUTTON_ID = 'new-button';
        let known_buttons = [];
        
        async function create_button() {
            let result = await make_request('/newdevice', 'POST');
            if (result.error) {
                return console.error(result.error, result.body);
            }
            
            let list;
            let err_ct = 0;
            while (true) {
                try {
                    list = await get_all_buttons();
                } catch (e) {
                    console.error('error fetching buttons', e);
                    err_ct += 1;
                    if (err_ct > 5) {
                        break;
                    }
                    continue;
                }
                if (list.length !== known_buttons.length) {
                    break;
                }
                await new Promise(resolve => {
                    setTimeout(resolve, 500)
                });
            }
            clear_button_list();
            for (const info of list) {
                append_new_button(info);
            }
        }
        
        function append_new_button(info) {
            let list = document.getElementById(BUTTON_LIST_ID);
            let container = document.createElement('div');
            container.classList.add('button-container');
            let button_title = document.createElement('span');
            button_title.classList.add('button-title');
            button_title.innerText = info.device_name;
            button_title.addEventListener('dblclick', async () => {
                button_title.contentEditable = true;
                async function changed() {
                    button_title.contentEditable = false;
                    if (button_title.innerText !== info.device_name) {
                        try {
                            await make_request('/newlabel', 'POST', {
                                device_id: info.device_id,
                                name: button_title.innerText,
                            });
                        } catch (e) {
                            button_title.innerText = info.device_name;
        
                        }
                        button_title.removeEventListener('blur', changed);
                    }
                }
                button_title.addEventListener('blur', changed);
        
            });
            let delete_btn = document.createElement('button');
            delete_btn.classList.add('delete-button')
            container.appendChild(button_title)
            let btns = document.createElement('div');
            btns.classList.add('button-group');
            let push_btn = document.createElement('button');
            push_btn.classList.add('button-action', 'push');
            push_btn.innerText = 'Push';
            push_btn.addEventListener('click', () => push_button(info.device_id))
            let hold_btn = document.createElement('button');
            hold_btn.innerText = 'Hold';
            hold_btn.classList.add('button-action', 'hold');
            hold_btn.addEventListener('click', () => hold_button(info.device_id))
            btns.appendChild(push_btn);
            btns.appendChild(hold_btn);
            container.appendChild(btns);
            list.appendChild(container);
        }
        
        async function push_button(id) {
            return make_request('/action', 'POST', {
                device_id: id,
                action: 'push',
            });
        }
        
        async function hold_button(id) {
            return make_request('/action', 'POST', {
                device_id: id,
                action: 'hold',
            });
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

            return fetch(url, opts).then(async res => {
                if (res.status !== 200) {
                    return {
                        error: res.statusText,
                        body: await res.text()
                    }
                } 
                return {
                    body: await res.json()
                }
            })
        }
        
        function clear_button_list() {
            let list = document.getElementById(BUTTON_LIST_ID);
            while (list.hasChildNodes()) {
                list.removeChild(list.lastChild);
            }
        }
        
        async function get_all_buttons() {
            let result = await make_request('/info');
            if (result.error) {
                console.error(result.body);
                throw new Error(result.error)
            }
            return result.body;
        }
        
        (() => {
            get_all_buttons().then(list => {
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

local function html()
    return [[<!DOCTYPE html>
<html>
    <head>
        <meta content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes" name="viewport">
        <meta charset="utf-8">
        <title>HTTP Button</title>
        <link rel="stylesheet" type="text/css" href="/style.css" />
    </head>
    <body>
        <header>
            <h1 style="text-align:center">HTTP Button</h1>
        </header>
        <div id="new-button-container">
            <button id="new-button">Add Button</button>
        </div>
        <div id="button-list-container">

        </div>
        <script type="text/javascript" src="/index.js" >
        </script>
    </body>
</html>
    ]]
end

return {
    html = html,
    js = js,
    css = css,
}
