# Dream Presence

This driver allows you to use a Unify Dream Machine as a presence sensor. It works by allowing you to register
hostname's as presence sensors. A good example of this is using your phone's hostname to act as a presence sensor
meaning that it will mark you as "present" when the phone is connected to the wifi network but "not present"
when your phone is not connected. 


## Setup

To set this driver up, first you would need to [enroll in my channel](https://bestow-regional.api.smartthings.com/invite/d4299AVZgQ2o) and install this driver.

Once installed, using the SmartThings app, navigate to the devices tab and touch the + on the top of the screen to add a
new device. On the next screen, you should have the option to "Scan Nearby", select this option.

After a short time, you should see a new device titled "Dream Presence". Back on the devices tab, touch the new device
card. On the device's screen you should see an ⁝ icon, touch this and select "settings". 

Here you will be prompted for 3 pieces of information

- Username: This is the UDM user you'd like to use to log in (36 character max)
- Password: This is the password for the corresponding username (36 character max)
- UDM IP: This is the ip address of your Dream Machine

I highly recommend that you create a readonly user for this driver to use.

### Creating a read only user

Log into your Dream Machine by visiting https://192.168.1.1 (Note your device may be configured at a different IP address),
on the bottom of the next page, there should be a "Users" button, select that.
From the users page, the top right should have an "Add User" button, when you select this it will drop down with options
choose "Add Admin". Select "Limited Admin" from the "Role" field and "local Access Only"
from the "Account Type" field. Finally
you can enter your chosen username and password and click "Add". Now you have a read only user.

Once you have this primary device created, you can add your first presence sensor. To do this, from the device screen
for your primary device, press the "Create Target" button. This will add a new devices named "Dream Presence Target"
(I recommend changing this to include the target hostname). From this new device's device screen, again touch the 
⁝ icon and select "settings". This will prompt you for 1 piece of information "Client Name" enter the hostname you'd
like to monitor.

### Finding your hostname

The Dream Machine's website's main page should have your network listed, click this to enter your UDM's admin page.
On the left side, there is a list of options, select the "Clients" option. This will bring you to a list of all the
devices connected to your network. The first column "Device" will be the hostname for your device. 


#### Iphone Users

If you want to configure your iphone to work with this driver, you may need to address the privacy mode of your home
wifi. If the "Private Wi-Fi Address" option is turned on, the "Device" will display to your iPhone's MAC address. This
is unfortunately not published as the hostname in the api endpoint we are hitting. You can disable this setting by
going to the "Settings" on your iPhone and selecting the "Wi-Fi" option, the network you are connected to should have
an ⓘ icon. When you touch this, it will bring you to this network's settings, one of which is "Private Wi-Fi Address",
you'll need to turn this option off.
