# Exit Detective

This driver illustrates an interim solution to subscribing to driver life-cycle events.

Currently it will never discover a device to predictably exit after discovery completes.

## Example

[![asciicast](https://asciinema.org/a/qIYXyruwaoXylBuAXi8s3gSGw.svg)](https://asciinema.org/a/qIYXyruwaoXylBuAXi8s3gSGw)

## Known Bugs

Currently, a previously noisy driver exiting may cause this event to happen immediately at
startup. This state is quite difficult to get into but a hot loop could cause the events
to never make it to the driver's process meaning they would be hanging around when the
driver starts up again. 
