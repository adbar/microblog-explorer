#!/bin/bash



# Create a temporary file
tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}
TMP1=$(tempfile)
trap 'rm -f $TMP1' EXIT


x=1


# Main loop
while (($x <= 100))
do
   python friendfeed-test.py
   sleep 2
   let x++
done


# Finalization
echo 'Finalizing...'

lines_number=$(cat users | wc -l)
echo -e "Users before uniq\t= ${lines_number}"
sort users | uniq > $TMP1
cp $TMP1 users
lines_number=$(cat users | wc -l)
echo -e "Users after uniq\t= ${lines_number}"

lines_number=$(cat links | wc -l)
echo -e "Links before uniq\t= ${lines_number}"
sort links | uniq > $TMP1
cp $TMP1 links
lines_number=$(cat links | wc -l)
echo -e "Links after uniq\t= ${lines_number}"

lines_number=$(cat rejected | wc -l)
echo -e "Rejected before uniq\t= ${lines_number}"
sort rejected | uniq > $TMP1
cp $TMP1 rejected
lines_number=$(cat rejected | wc -l)
echo -e "Rejected after uniq\t= ${lines_number}"
