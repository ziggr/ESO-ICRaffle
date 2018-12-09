.PHONY: send get csv

put:
	rsync -vrt --delete --exclude=.git \
		--exclude=published \
		--exclude=doc \
		--exclude=data \
		--exclude=test \
		. /Volumes/Elder\ Scrolls\ Online/live/AddOns/ICRaffle

get:
	cp -f /Volumes/Elder\ Scrolls\ Online/live/SavedVariables/ICRaffle.lua data/

out:
	lua ICRaffle_to_text.lua

zip:
	-rm -rf published/ICRaffle published/ICRaffle\ x.x.x.x.zip
	mkdir -p published/ICRaffle
	cp ./ICRaffle* published/ICRaffle/
	cd published; zip -r ICRaffle\ x.x.x.x.zip ICRaffle
	-rm -rf published/ICRaffle

