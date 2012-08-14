#!/usr/bin/python

###	This script is part of the microblog-explorer project (https://github.com/adbar/microblog-explorer).
###	It is brought to you by Adrien Barbaresi.
###	It is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used with the output of a language identification system (https://github.com/saffsd/langid.py).

from __future__ import division
from __future__ import print_function
from collections import defaultdict

import optparse

## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')

parser.add_option('-lc', '--language-codes',
	action="store_true", dest="lcodes", default=False,
	help="be prompted for language codes to show")
parser.add_option("-f", "--file", dest="filename",
	help="input file name", metavar="FILE")

options, args = parser.parse_args()

if options.filename is None:
	parser.error('No filename given')

## Initialize
langd = defaultdict(int)
urld = defaultdict(int)

if options.lcodes is True:
	inp = raw_input('Languages wanted (comma-separated codes) : ')
	langlist = inp.split(',')

f = open(options.filename, 'r')


## Parse input file
for line in f:
	columns = line.split('\t')
	if len(columns) == 3:
		if columns[0] not in urld:
			langd[columns[1]] += 1
			urld[columns[0]] = columns[1]
f.close()


## Display and print the results
print (len(urld), 'total unique urls')
for l in sorted(langd, key=langd.get, reverse=True):
	pcent = (langd[l] / len(urld))*100
	print (l, langd[l], '%.1f' % round(pcent, 1), sep='\t')

if options.lcodes is True:
	out = open('sample-choice', 'w')
	for lang in langlist:
		for key in urld:
			if urld[key] == lang:
				out.write(key + '\t' + urld[key] + '\n') 
	out.close()