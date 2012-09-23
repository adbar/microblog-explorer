#!/bin/bash


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


# TODO:
## advanced divide and conquer and/or URL pool


if (($# < 3)) || (($# > 4))
then
	echo "Usage : [list of urls] [number of requests] [number of threads] [seen urls file (optional)]"
	exit 1
fi

if (($3 > 10))
then
	echo "No more than 10 threads please."
	exit 1
fi


listfile=$1
req=$2
num_files=$3

# Find a mean number of lines per file
total_lines=$(cat ${listfile} | wc -l)

if (($req < $total_lines))
then
	head -${req} ${listfile} > TEMP1
	listfile=TEMP1
	((lines_per_file = (req + num_files - 1) / num_files))
else
	((lines_per_file = (total_lines + num_files - 1) / num_files))
fi


# Split the actual file, maintaining lines
## splitting trick found here : http://stackoverflow.com/questions/7764755/unix-how-do-a-split-a-file-into-equal-parts-withour-breaking-the-lines
split -a 1 -d --lines=${lines_per_file} ${listfile} LINKS-TODO.

# Debug information
echo -e "Total lines\t= ${total_lines}"
echo -e "Lines per file\t= ${lines_per_file}"

i=0
for f in LINKS-TODO.*
do
	perl resolve-redirects.pl -t 10 --all --filesuffix $i $f &
	sleep 2
	((i++))
done

wait

# Merge the files
#cat LINKS-TODO.* > TODO # not necessary
rm LINKS-TODO.*
cat BAD-HOSTS.* >> BAD-HOSTS
rm BAD-HOSTS.*
cat OTHERS.* > LINKS-TODO-redchecked
rm OTHERS.*
cat REDIRECTS.* >> LINKS-TODO-redchecked
rm REDIRECTS.*
cat red-ERRORS.* >> red-ERRORS
rm red-ERRORS.*

# Make sure all lines are unique
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP1=$(tempfile)
trap 'rm -f $TMP1' EXIT

sort BAD-HOSTS | uniq > $TMP1
mv $TMP1 BAD-HOSTS
sort LINKS-TODO-redchecked | uniq > $TMP1
mv $TMP1 LINKS-TODO-redchecked

# Backup the final result
tar -cjf red-backup.tar.bz2 BAD-HOSTS LINKS-TODO-redchecked red-ERRORS
