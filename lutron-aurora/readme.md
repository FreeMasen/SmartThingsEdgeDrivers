# Lutron Aurora

Adds preliminary support for the Lutron Aurora button/dimmer.

- button press
  - As apposed to using the switch capability for on/off, this driver will emit a button press
  - No double-press or hold events are available
- dimmer
  - Dimmer events are interpreted as either increase or decrease based on the direction they
    are turned, this maps to the preference for `stepSize` which will determine what % an increase
    or decrease represents
  - I have tested this with 3 different Aurora's from the factory (one of which was joined to hue)
    and observed that the decrease event always sends 2 and increase always sends > 3 but I
    wouldn't be surprised if other devices act differently.
