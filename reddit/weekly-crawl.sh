#!/bin/bash


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


# Append to / create a log file 
echo "`date`:$@" >> reddit-crawl.log

# Check if an archive already exists
archive=reddit-crawl.tar.bz2
if [ -f $archive ]
	then
	tar -xjf $archive
fi

# Language codes currently implemented
lcodes=( "cs" "da" "de" "es" "fi" "fr" "it" "no" "po" "pt" "ro" )

# Create a temporary file
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}

TMP1=$(tempfile)

trap 'rm -f $TMP1' EXIT

# Main loop, calls the api-crawl script
for lang in ${lcodes[@]}; do

	python api-crawl.py -l $lang &>> reddit-crawl.log

	EXT=$lang"_external"
	EXTUS=$lang"_extuserslinks"
	US=$lang"_users"
	INT=$lang"_internal"
	SUSP=$lang"_suspicious"
	filelist=($EXT $EXTUS $US $INT $SUSP)

	for f in ${filelist[@]}; do
		if [ -f $f ]
		then
			# use the temporary file to check for duplicates
			sort $f | uniq > $TMP1
			mv $TMP1 $f
		fi
	done

done

# Compress the lists
tar -cjf reddit-crawl.tar.bz2 *_*
