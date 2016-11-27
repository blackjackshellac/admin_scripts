#!/bin/bash

esudo() {
	echo $*
	sudo $*
}

esudo /usr/bin/gem install rdoc-data
esudo /usr/local/bin/rdoc-data --install
esudo /usr/bin/gem rdoc --all --overwrite

