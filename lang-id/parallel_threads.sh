#!/bin/bash


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used with the output of a language identification system (https://github.com/saffsd/langid.py).

## example of use:
## (python langid.py -s --host=localhost -l en,cs,de,sk,fr,pl,it,es,ja,nl,ru,he,hu,sl,hr,pt,sv,fi,et,no,lt,da,ro,bs,tr,ar,ka,ca,el,uk,is,bg,lv,vi,sw,sr,eo,nb,ga,eu &> lang-id.log &)
## (bash parallel_threads.sh list-of-links 50000 6 &> logfile.log &)


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


# Work out lines per file.
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
	### starting the threads
	if (($# == 4))
	then
		perl fetch-send-furl.pl --seen $4 --hostreduce --all --filesuffix $i $f &
	else
		perl fetch-send-furl.pl --hostreduce --all --filesuffix $i $f &
	fi
	sleep 0.5
	((i++))
done

wait

# Merge the files
cat RESULTS-langid.* >> RESULTS
rm RESULTS-langid.*
cat LINKS-TODO.* > TODO
rm LINKS-TODO.*
cat LINKS-TO-CHECK.* >> TO-CHECK
rm LINKS-TO-CHECK.*

# Make sure all lines are unique
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP1=$(tempfile)
trap 'rm -f $TMP1' EXIT

sort RESULTS | uniq > $TMP1
mv $TMP1 RESULTS

sort TO-CHECK | uniq > $TMP1
mv $TMP1 TO-CHECK

sort TODO | uniq > $TMP1
mv $TMP1 TODO

# Backup the final result
tar -cjf backup.tar.bz2 RESULTS TO-CHECK TODO

# rm TEMP1 ?