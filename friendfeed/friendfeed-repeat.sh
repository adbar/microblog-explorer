#!/bin/bash


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


# TODO:
# TIMEOUT: timeout 3550s -s 9
# http://stackoverflow.com/questions/687948/timeout-a-command-in-bash-without-unnecessary-delay
# functions !


# Create the necessary files

if [ ! -f ff-users-global ]
then
	touch ff-links-global
fi

if [ ! -f ff-rejected-global ]
then
	touch ff-rejected-global
fi


# Create a temporary file
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP=$(tempfile)
trap 'rm -f $TMP' EXIT


x=1
# Main loop
while (($x <= 20))
do
   python friendfeed-static.py &
   sleep 10
   python friendfeed-static.py &
   sleep 10
   python friendfeed-static.py &
   sleep 10
   python friendfeed-static.py &
   wait
   sleep 5
   sort ff-usersdone | uniq > $TMP
   mv $TMP ff-usersdone
   let x++
done


# Finalization
echo 'Finalizing...'

sort ff-usersdone | uniq > $TMP
mv $TMP ff-usersdone
lines_number=$(cat ff-usersdone | wc -l)
echo -e "Total users after uniq\t= ${lines_number}"

lines_number=$(cat ff-links | wc -l)
echo -e "Links before uniq\t= ${lines_number}"
sort ff-links | uniq > $TMP
mv $TMP ff-links
lines_number=$(cat ff-links | wc -l)
echo -e "Links after uniq\t= ${lines_number}"
cat ff-links-global ff-links | sort | uniq > $TMP
mv $TMP ff-links-global
lines_number=$(cat ff-links-global | wc -l)
echo -e "Total links\t= ${lines_number}"
rm ff-links

lines_number=$(cat ff-rejected | wc -l)
echo -e "Rejected before uniq\t= ${lines_number}"
sort ff-rejected | uniq > $TMP
mv $TMP ff-rejected
lines_number=$(cat ff-rejected | wc -l)
echo -e "Rejected after uniq\t= ${lines_number}"
cat ff-rejected-global ff-rejected | sort | uniq > $TMP
mv $TMP ff-rejected-global
lines_number=$(cat ff-rejected-global | wc -l)
echo -e "Total Rejected\t= ${lines_number}"
rm ff-rejected
