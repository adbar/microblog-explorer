#!/bin/bash


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


tempfile() {
    tempprefix=$(basename "$0")
    mktemp /tmp/${tempprefix}.XXXXXX
}

TMP1=$(tempfile)
TMP2=$(tempfile)

trap 'rm -f $TMP1' EXIT
trap 'rm -f $TMP2' EXIT

sort result-ext | uniq > $TMP1
sort result-int | uniq > $TMP2
mv $TMP1 result-ext
mv $TMP2 result-int
