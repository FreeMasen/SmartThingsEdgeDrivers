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

#create-container {
    margin: auto;
    width: 5000px;
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
        const create_button = document.getElementById("create-button");
        const get_report_button = document.getElementById("get-report");
        const profile_select = document.getElementById("create-profile");
        const number_input = document.getElementById("create-number");
        create_button.addEventListener("click", () => {
            
        });

    ]]
end

local function html()
    return [[<!DOCTYPE html>
<html>
    <head>
        <meta content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes" name="viewport">
        <meta charset="utf-8">
        <title>Prefs Memory</title>
        <link rel="stylesheet" type="text/css" href="/style.css" />
    </head>
    <body>
        <header>
            <h1 style="text-align:center">Prefs Memory</h1>
        </header>
        
        <div id="create-container">
            <input type="number" id="create-number" />
            <select id="create-profile">
                <option value="no-prefs"></option>
                <option value="ten-prefs"></option>
                <option value="twenty-prefs"></option>
            </select>
            <button id="create-button">Bulk Add Devices</button>
        </div>
        <div id="report-container">
        </div>
        <div>
            <button id="get-report">Get Report</button>
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
