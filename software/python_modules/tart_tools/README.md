# TART: Radio-telescope command line tools
    
This module provides command line tools for operating Transient Array Radio Telescope (TART). These tools are

* tart_image
* tart_calibrate
* tart_calibration_data

To generate an image from a telescope, try the following command which should display the current view from a telescope
on top of Signal-Hill near Dunedin New Zealand.

    tart_image --api https://tart.elec.ac.nz/signal --display

For more information see the [TART Github repository](https://github.com/tmolteno/TART)

## Install Instructions

tart_tools is available from standard python package repositories. Try:

    pip install tart_tools


## Authors

* Tim Molteno (tim@elec.ac.nz)
* Max Scheel (max@max.ac.nz)

## Development work
    
If you are developing this package, this should be installed using
```
	make develop
```
in which case changes to the source-code will be immediately available to projects using it.

    