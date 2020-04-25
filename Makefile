key?=$(shell cat params/key 2>/dev/null)
srs?=$(shell cat params/srs 2>/dev/null || echo 4326)
res?=$(shell cat params/res 2>/dev/null || echo 0.01)
nodata_value?=$(shell cat params/nodata_value 2>/dev/null || echo -2)
radius?=$(shell cat params/radius 2>/dev/null || echo 50000)
bbox?=$(shell cat params/bbox 2>/dev/null || echo ALL)
imagebbox?=$(shell cat params/imagebbox 2>/dev/null || echo AUTO)
steps?=$(shell cat params/steps 2>/dev/null || echo 0%,25%,50%,75%)
cols?=$(shell cat params/cols 2>/dev/null || echo white_red)
colour_mode?=exact

.PRECIOUS: points_k_$(key)_bbox$(bbox).zip heatmap_k_%.tiff extract_%.osm.pbf data_%.osm.pbf water-polygons-split-%.zip %_land.tiff %.tiff

.PHONY: montage_all_top_%

params:
	mkdir $@

build-deps:
	sudo apt-get -q install --yes graphicsmagick libimage-exiftool-perl pyosmium osmium-tool gdal-bin
	dpkg --compare-versions $$(dpkg-query -f='$${Version}' --show gdal-bin) lt 2.4 && ( echo "Your version of gdal-bin (ogr2ogr) is $$(dpkg-query -f='$${Version}' --show gdal-bin) < 2.4. ogr2pgr v2.4+ is required." ; exit 2 )
	cargo install sheatmap pastel

# Fake targets to save parameters
res-%: | params
	echo $* > params/res
key-%: | params
	echo $* > params/key
radius-%: | params
	echo $* > params/radius
srs-%: | params
	echo $* > params/srs
steps-%: | params
	echo $* > params/steps
cols-%: | params
	echo $* > params/cols
bbox-%: | params
	echo $* > params/bbox
imagebbox-%: | params
	echo $* > params/imagebbox

reset-param-%: | params
	-rm -f params/$*

reset-all-params: reset-param-res reset-param-key reset-param-radius reset-param-srs reset-param-steps reset-param-cols reset-param-bbox reset-param-imagebbox

download.geofabrik.de/%:
	wget -nc https://download.geofabrik.de/$*-latest.osm.pbf
	-pyosmium-up-to-date -vv $(notdir $*)-latest.osm.pbf
	-rm -f data.osm.pbf
	ln -s $(notdir $*)-latest.osm.pbf data.osm.pbf

data-ireland: srs-2157 res-1000 radius-50000 imagebbox-418829,511786,786046,964700 download.geofabrik.de/europe/ireland-and-northern-ireland 
data-ireland-and-britain: srs-2157 res-1000 radius-50000 imagebbox-386592,235671,1311592,1585671 download.geofabrik.de/europe/britain-and-ireland
data-europe: srs-3035 res-10000 radius-50000 download.geofabrik.de/europe

data_bbox$(bbox).osm.pbf: data.osm.pbf
	$(eval TEMPFILE=$(shell mktemp tmp.$@.XXXXX.osm.pbf))
	osmium extract --overwrite --bbox $(bbox) -o $(TEMPFILE) $<
	mv $(TEMPFILE) $@

data_bboxALL.osm.pbf: data.osm.pbf
	ln -s $< $@

water-polygons-split-4326.zip:
	wget -N https://osmdata.openstreetmap.de/download/water-polygons-split-4326.zip

water-polygons-split-4326/water_polygons.shp: water-polygons-split-4326.zip
	unzip -u $<
	touch water-polygons-split-4326/water_polygons.*

water-polygons-split-$(srs)/water_polygons.shp: water-polygons-split-4326/water_polygons.shp
	$(eval TEMPDIR=$(shell mktemp -d tmp.water-polygons-split-$(srs).XXXX.d))
	ogr2ogr -s_srs epsg:4326 -t_srs epsg:$(srs) $(TEMPDIR)/water_polygons.shp ./water-polygons-split-4326/water_polygons.shp -skipfailures
	shapeindex $(TEMPDIR)/water_polygons.shp
	mv $(TEMPDIR) water-polygons-split-$(srs)

# Extract all osm objs with this key
extract_k_$(key)_bbox$(bbox).osm.pbf: data_bbox$(bbox).osm.pbf
	osmium tags-filter $< --overwrite -o $@ $(key)

# Extract all osm objs with this key & value
extract_kv_$(key)_%_bbox$(bbox).osm.pbf: extract_k_$(key)_bbox$(bbox).osm.pbf
	osmium tags-filter $< --overwrite -o $@ $(subst __,=,$*)

# This key as a geojsons file
raw_k_%_bbox$(bbox).geojsons.gz: extract_k_%_bbox$(bbox).osm.pbf
	$(eval TEMPFILE=$(shell mktemp tmp_convert_to_geojsons_XXXX.csv.gz))
	osmium export --add-unique-id=counter --output-format geojsonseq -o - $< | gzip > $(TEMPFILE)
	mv $(TEMPFILE) $@

# Shapefile of those points
points_k_%_bbox$(bbox).zip: raw_k_%_bbox$(bbox).geojsons.gz
	$(eval TEMPFILE=$(shell mktemp tmp_convert_to_geojsons_XXXX.csv))

	# Large files can break the sqlite process, so convert to CSV first to remove all tags
	ogr2ogr -f CSV -select '$*' $(TEMPFILE) /vsigzip/$< -lco GEOMETRY=AS_WKT -skipfailures
	ogr2ogr -a_srs epsg:4326 -f "ESRI Shapefile" -sql "SELECT $*, ST_Centroid(geometry) from $(TEMPFILE:.csv=)" -dialect sqlite $(@:zip=shp) $(TEMPFILE)
	rm -f $(TEMPFILE)
	shapeindex $(@:zip=shp)
	zip $@ $(@:zip=shp) $(@:zip=shx) $(@:zip=prj) $(@:zip=dbf) $(@:zip=index)
	rm $(@:zip=shp) $(@:zip=shx) $(@:zip=prj) $(@:zip=dbf) $(@:zip=index)

points_kv_$(key)__%_bbox$(bbox).zip: points_k_$(key)_bbox$(bbox).zip
	$(eval TEMPDIR=$(shell mktemp -d tmp.$@.XXXX.d))
	ogr2ogr -f 'ESRI Shapefile' -where "$(key) LIKE '%$*%'" $(TEMPDIR)/$(@:zip=shp) /vsizip/$</$(<:zip=shp)
	shapeindex $(TEMPDIR)/$(@:zip=shp)
	zip -j $@ $(TEMPDIR)/*
	rm -rf $(TEMPDIR)


# What are the popular values 
list_values_%_bbox$(bbox).txt: extract_k_%_bbox$(bbox).osm.pbf
	$(eval TEMPFILE=$(shell mktemp tmp.XXXX.txt))
	osmium cat -f xml -o - $< | grep -oP '(?<= k="$*" v=").+?(?=")' | tr ';' '\n' | sed -e 's/^ *//' -e 's/ *$$//' | sort | uniq -c | sort -nr > $(TEMPFILE)
	mv $(TEMPFILE) $@


top_%_$(key): list_values_$(key)_bbox$(bbox).txt
	$(eval TARGETS=$(shell cat list_values_$(key)_bbox$(bbox).txt | cut -c9- | head -n $* | sed "s/.*/percent_$(key)__&_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered3_$(colour_mode)_$(cols)_$(steps)_stamped.png/"))
	@echo $(TARGETS)
	$(MAKE) $(TARGETS)


raw_points_%_srs$(srs)_bbox$(bbox).csv: points_%_bbox$(bbox).zip
	ogr2ogr -t_srs epsg:$(srs) -f CSV -lco GEOMETRY=AS_XY $@ /vsizip/$</$(<:zip=shp)

heatmap_%_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).xyz.gz: raw_points_%_srs$(srs)_bbox$(bbox).csv
	#[brigid][~/osm/2020-raster-summary-maps]$ echo -12.45,49.42,2.55,61.25 | cut -d, -f1,2 | tr , " "  | gdaltransform -s_srs epsg:4326 -t_srs epsg:2157 -output_xy | tr " " ,
	RUST_LOG=info sheatmap -i $< -o $@ --res $(res) $(res) --bbox $(imagebbox) --radius $(radius)

heatmap_$(key).tiff: heatmap_k_$(key)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff
	mv $< $@

heatmap_$(key)__$(value).tiff: heatmap_kv_$(key)__$(value)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff
	mv $< $@

heatmap_%.tiff: heatmap_%.xyz.gz
	gdal_translate -a_srs epsg:$(srs) /vsigzip/$< $@

merged_$(key)__%_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff: heatmap_k_$(key)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff heatmap_kv_$(key)__%_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff
	# Merge them together so they all get the same resolution & size
	gdal_merge.py -separate -o $@ $^
	#python raster_band_description.py $@ 1 "$(key) heatmap score"
	#python raster_band_description.py $@ 2 "$(key)=$(value) heatmap score"

percent_%_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff: merged_%_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff
	$(eval TEMPFILE1=$(shell mktemp tmp.percent.XXXX.tiff))
	gdal_calc.py --NoDataValue=$(nodata_value) -A $< --A_band=1 -B $< --B_band=2 --overwrite --outfile=$(TEMPFILE1) --calc="clip((A<=0)*0 + (A>0)*(true_divide(B, A, where=A>0)*100), 0, 100)"
	gdal_merge.py -separate -o $@ $< $(TEMPFILE1)
	#python raster_band_description.py $@ 3 "$(key)=$(value) as % of $(key) (heatmap score)"
	rm $(TEMPFILE1)

%_diff.tiff: %_merged.tiff
	gdal_calc.py --NoDataValue=$(nodata_value) -A $< --A_band=1 -B $< --B_band=2 --overwrite --outfile=$@ --calc="A-B"

%_land.tiff: %.tiff water-polygons-split-$(srs)/water_polygons.shp params/nodata_value
	$(eval BANDS=$(shell gdalinfo -json $< | jq ".bands[].band"))
	$(eval BANDS_ARG=$(foreach B,$(BANDS),-b $(B)))
	$(eval TEMPDIR=$(shell mktemp -d tmp.$*.XXXX))
	gdal_translate -a_nodata $(nodata_value) $< $(TEMPDIR)/input.tiff
	gdal_rasterize $(BANDS_ARG) -burn $(nodata_value) water-polygons-split-$(srs)/water_polygons.shp $(TEMPDIR)/input.tiff
	rm -f $@ $@.aux.xml
	mv $(TEMPDIR)/input.tiff $@
	rm -rf $(TEMPDIR)

%_compressed.tiff: %.tiff
	gdal_translate -co COMPRESS=LZW -co PREDICTOR=3 -co TILED=YES $< $@

%_stamped.png: %.png
	gm convert $< -fill black -pointsize 20 label:"© CC-BY-SA $(shell date '+%Y') www.technomancy.org | $(shell date '+%-d %b %Y') | Map Data: © OpenStreetMap. ODbL 1.0" -gravity NorthWest -append $@
	exiftool -overwrite_original -Artist="techomancy.org" -Copyright="Licenced under Creative Commons Attribution ShareAlike 4.0 International License. Based on data from the OpenStreetMap project, which is under the ODbL 1.0 licence" -XMP-cc:License="http://creativecommons.org/licenses/by-sa/4.0/" $@
	optipng -quiet $@
	-rm -f last.png
	ln -s $@ last.png

%.png: %.tiff
	gm convert -flip $< $@
	exiftool -Copyright="Licenced under Creative Commons Attribution ShareAlike 4.0 International License. Based on data from the OpenStreetMap project, which is under the ODbL 1.0 licence" -XMP-cc:License="http://creativecommons.org/licenses/by-sa/4.0/" $@
	optipng -quiet $@
	-rm $@_original

%_rendered1_$(colour_mode)_$(cols)_$(steps).tiff: %.tiff colour_ramp_$(colour_mode)_$(cols)_$(steps).txt
	gdaldem color-relief -b 1 $< colour_ramp_$(colour_mode)_$(cols)_$(steps).txt $@

%_rendered2_$(colour_mode)_$(cols)_$(steps).tiff: %.tiff colour_ramp_$(colour_mode)_$(cols)_$(steps).txt
	gdaldem color-relief -b 2 $< colour_ramp_$(colour_mode)_$(cols)_$(steps).txt $@

%_rendered3_$(colour_mode)_$(cols)_$(steps).tiff: %.tiff colour_ramp_$(colour_mode)_$(cols)_$(steps).txt
	gdaldem color-relief -b 3 $< colour_ramp_$(colour_mode)_$(cols)_$(steps).txt $@

%_rendered7_$(colour_mode)_$(cols)_$(steps).tiff: %.tiff colour_ramp_$(colour_mode)_$(cols)_$(steps).txt
	gdaldem color-relief -b 7 $< colour_ramp_$(colour_mode)_$(cols)_$(steps).txt $@

heatmap_key: heatmap_k_$(key)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered1_$(colour_mode)_$(cols)_$(steps)_stamped.png
	-rm -f last.png
	ln -s $< last.png
	@echo 
	@echo Your file is ready in $<
	@echo 

heatmap_key_value: heatmap_kv_$(key)__$(value)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered1_$(colour_mode)_$(cols)_$(steps)_stamped.png
	-rm -f last.png
	ln -s $< last.png
	@echo 
	@echo Your file is ready in $<
	@echo 

percent:  percent_$(key)__$(value)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered3_$(colour_mode)_$(cols)_$(steps)_stamped.png
	-rm -f last.png
	ln -s $< last.png
	@echo 
	@echo Your file is ready in $<
	@echo 

#percent: percent_$(key)__$(value)

compare_$(key)__$(value1)__$(value2)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff: \
			percent_$(key)__$(value1)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff \
			percent_$(key)__$(value2)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff
	
	$(MAKE) value=$(value1) percent_$(key)__$(value1)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff
	$(MAKE) value=$(value2) percent_$(key)__$(value2)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox).tiff
	
	$(eval TEMPFILE1=$(shell mktemp tmp.compare.1.$(key)__$(value1)__$(value2).XXXX.tiff))
	
	# Merge them together so they all get the same resolution & size
	gdal_merge.py -separate -o $(TEMPFILE1) $^
	
	$(eval TEMPFILE2=$(shell mktemp tmp.compare.2.$(key)__$(value1)__$(value2).XXXX.tiff))
	gdal_calc.py --overwrite --calc "A-B" -A $(TEMPFILE1) --A_band=3 -B $(TEMPFILE1) --B_band=6 --outfile=$(TEMPFILE2)
	
	gdal_merge.py -separate -o $@ $^ $(TEMPFILE2)
	-rm $(TEMPFILE1) $(TEMPFILE2)


compare: compare_$(key)__$(value1)__$(value2)_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered7_$(colour_mode)_$(cols)_$(steps).png
	-rm -f last.png
	ln -s $< last.png
	@echo 
	@echo Your file is ready in $<
	@echo 

list_values: list_values_$(key)_bbox$(bbox).txt

all_top_%: top_%_$(key)


colour-ramp: colour_ramp_$(colour_mode)_$(cols)_$(steps).txt

colour_ramp_$(colour_mode)_$(cols)_$(steps).txt: generate_colour_ramp.py
	$(eval TEMPFILE_OUTPUT=$(shell mktemp tmp.colour_ramp_$(colour_mode)_$(cols)_$(steps).output.XXXXX.txt))
	python generate_colour_ramp.py $(cols) $(steps) $(colour_mode) > $(TEMPFILE_OUTPUT)
	mv $(TEMPFILE_OUTPUT) colour_ramp_$(colour_mode)_$(cols)_$(steps).txt

#montage_all_top_%: montage_top_%_$(key)_bbox$(bbox)_stamped.png
montage_all_top_%: montage_top_%_$(key)_bbox$(bbox)_stamped.png

montage_top_%_$(key)_bbox$(bbox).png: list_values_$(key)_bbox$(bbox).txt
	$(eval TARGETS=$(shell cat list_values_$(key)_bbox$(bbox).txt | cut -c9- | head -n $* | sed "s/.*/percent_$(key)__&_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered3_$(colour_mode)_$(cols)_$(steps).png/"))
	@echo $(TARGETS)
	$(MAKE) $(TARGETS)
	$(eval MONTAGE_FILES=$(shell cat list_values_$(key)_bbox$(bbox).txt | cut -c9- | head -n $* | sed "s/.*/ -l & percent_$(key)__&_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered3_$(colour_mode)_$(cols)_$(steps).png/ | tr-d '\n'"))
	gm montage -pointsize 80 $$(cat list_values_$(key)_bboxALL.txt | cut -c9- | head -n $* | while read VALUE ; do echo " -label $${VALUE} percent_$(key)__$${VALUE}_srs$(srs)_res$(res)_radius$(radius)_bbox$(bbox)_imagebbox$(imagebbox)_land_rendered3_$(colour_mode)_$(cols)_$(steps).png " ; done | tr -d '\n') -geometry '+1+1>' $@
