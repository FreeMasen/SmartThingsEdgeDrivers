# Octoprint

This Driver is a smartthings integration for the [octoprint](https://octoprint.org/). It currently has 3 components.

1. Switch - on for print is running, turn it off to cancel an active print job
1. Bed - Displays the target and current temperature in C
1. Tool - Displays the target and current temperature in C

This driver relies on a few plugins for octoprint which are enabled by default. The first is the ssdp plugin,
this allows the driver to discover octoprint servers on your network. The second is the
[application keys](https://docs.octoprint.org/en/master/bundledplugins/appkeys.html?highlight=appkeys#post--api-plugin-appkeys)
plugin which allows you to authorize the driver to control your printer without having to copy/paste a long api key.

## Authorization

When a printer is initially discovered, it will attempt to gain authorization, this requires a username for a user
on the octoprint server, which can be provided via the device settings/preferences in the smartthigns app. You should
set this value to the user name you log into octoprint with (you can find this on the top right of the main octoprint web
interface). Once this is provided, it will request access from the server, navigating to the octoprint main web interface
you should be prompted for something like 

![access request](https://docs.octoprint.org/en/master/_images/bundledplugins-appkeys-confirmation_prompt.png)

The app name will be "SmartThings Octopi Driver", once you select "Allow" it the driver will then begin polling your
octoprint server for the connected printer's state.

