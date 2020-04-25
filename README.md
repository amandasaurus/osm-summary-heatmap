Making maps showing the distribution of data in OSM

# Installation

    make build-deps

Rust is required.

# Example

What percentage of all `cuisines` are for Fish & Chips in Ireland & Britain

    make data-ireland-and-britain
    make percent steps=0,5,65,10,12.5,15,20 cols=white_red key=cuisine value=fish_and_chips

White means less, red is more. There is a large hole in London, because it's a large city, so there is a greater choice of restaurants and take-aways, so _as a percentage_ fish & chips shops are lower.

[Sports in Ireland & Britain in OSM]() shows 

# Commands

Often it will print out the filename that was generated. The file `last.png` will be symlinked to that.

## `percent`

Needs `key` & `value` parameters. Displays what percentage of items with that `key` have that `value`.

## `heatmap_key`

Needs `key` parameter. Heatmap of the distribution of `key`.

## `heatmap_key-value`

Needs `key` & `value` parameters. Heatmap of the distribution of `key=value` tag.

# Common options

## `srs`

The Spatial Reference System to use. it's units are used for the radius.

## `res`

When generating the heatmap, use the value as the resolution of the image. Units of the SRS.

## `radius`

The radius of the heatmap, in units of the SRS

## Colours of the map

`gdaldem color-relief` is used to generate a coloured GeoTIFF file. the `cols` parameter is a `_` separated list of colours to generate the ramp from, using `pastel`'s HSL colour ramp. `steps` is a `,` separate list of 'steps' in the colour ramp. Either raw values, or `%`'s can be used. `%` means gdal uses that percentage of the maximum value in the data. With `colour_mode=exact` (the default) all input data from that value up to the next value are set to that colour value. With another `colour_mode` value, the regular gdal colour smoothing & interpolation is done.

Default is `cols=white_red steps=0%,25%,50%,75%`. Set it with `make cols-white_blue`/`make steps=0,100,1000` (or use the `cols=`/`steps=` Make variable)

The `generate_colour_ramp.py` script creates a gdal colour ramp file with a name like `colour_ramp_exact_white_red_0%,10%.txt`

## `steps`

Comma separated list of step values.  You probably want `0` (or `0%`) as the first entry.

## `cols`

The colour ramp is build from these value. Use `_` to separate values. `white_blue` means “go from white to blue”. `white_blue_red`: “From white to blue to red”. `white_502917`: “From white to `#502917`”.

Colour ramps are generated with `pastel`.

### Examples

### `cols=white_red steps=0%,10%,90%`

`white` (i.e. `#ffffff`) is set at the 0% value, `red` (`#ff0000`) for `90%`, and values at 10% are coloured with half way between them according to pastel (`#ff9e81`).

# Tips

## Interactively viewing images

On Ubuntu Linux, the image viewer `geeqie` will reload a file when it changes. I open it, and display the `last.png` file, and iteratively modify the `steps` value and can see those changes quickly.

## What are the values in a heatmap?

For the `steps` value, you can use percentages, or raw values.  `gdalinfo -stats` (e.g. `gdalinfo -stats heatmap_kv_sport__golf_srs2157_res1000_radius50000_bboxALL_imagebbox386592,235671,1311592,1585671.tiff`) gives an overview of the values in the heatmap:

    Band 1 Block=925x2 Type=Float32, ColorInterp=Gray
      Min=0.000 Max=1019.677 
      Minimum=0.000, Maximum=1019.677, Mean=24.859, StdDev=75.753
      Metadata:
        STATISTICS_MAXIMUM=1019.6765136719
        STATISTICS_MEAN=24.85914913463
        STATISTICS_MINIMUM=0
        STATISTICS_STDDEV=75.753194758544
        STATISTICS_VALID_PERCENT=100

Here the values of each pixel go from 0 to 1019.

# Copyright

Copyright 2020, Affero GNU General Public Licence v3 or later. Maps produced will be a Produced Work of OpenStreetMap, and hence require attribution.
