#!/bin/bash


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


sort result-ext | uniq > r-ext2
sort result-int | uniq > r-int2
mv r-ext2 result-ext
mv r-int2 result-int
