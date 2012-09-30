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
while (($x <= 20))
do
   python friendfeed-test.py -dv &
   sleep 10
   python friendfeed-test.py -dv &
   sleep 10
   python friendfeed-test.py -dv &
   sleep 10
   python friendfeed-test.py -dv &
   wait
   let x++
done


# Finalization
echo 'Finalizing...'

lines_number=$(cat ff-usersdone | wc -l)
echo -e "Users before uniq\t= ${lines_number}"
sort ff-usersdone | uniq > $TMP1
cp $TMP1 ff-usersdone
lines_number=$(cat ff-usersdone | wc -l)
echo -e "Users after uniq\t= ${lines_number}"

lines_number=$(cat ff-links | wc -l)
echo -e "Links before uniq\t= ${lines_number}"
sort ff-links | uniq > $TMP1
cp $TMP1 ff-links
lines_number=$(cat ff-links | wc -l)
echo -e "Links after uniq\t= ${lines_number}"

lines_number=$(cat ff-rejected | wc -l)
echo -e "Rejected before uniq\t= ${lines_number}"
sort ff-rejected | uniq > $TMP1
cp $TMP1 ff-rejected
lines_number=$(cat ff-rejected | wc -l)
echo -e "Rejected after uniq\t= ${lines_number}"
