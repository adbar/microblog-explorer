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

parser.add_option('-l', '--language-codes',
	action="store_true", dest="lcodes", default=False,
	help="prompt for language codes and output of corresponding links")
parser.add_option("-i", "--input-file", dest="inputfile",
	help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile",
	help="output file name (default : output to STDOUT)", metavar="FILE")

options, args = parser.parse_args()

if options.inputfile is None:
	parser.error('No input file given')

## Initialize
langd = defaultdict(int)
urld = defaultdict(int)
intd = defaultdict(int)

if options.lcodes is True:
	inp = raw_input('Languages wanted (comma-separated codes) : ')
	langlist = inp.split(',')

f = open(options.inputfile, 'r')


## Parse input file
for line in f:
	columns = line.split('\t')
	if len(columns) == 3:
		if columns[0] not in urld:
			langd[columns[1]] += 1
			urld[columns[0]] = columns[1]
			if options.lcodes is True:
				intd[columns[0]] = columns[2].rstrip()
f.close()


## Display and print the results
print (len(urld), 'total unique urls')
for l in sorted(langd, key=langd.get, reverse=True):
	pcent = (langd[l] / len(urld))*100
	print (l, langd[l], '%.1f' % round(pcent, 1), sep='\t')

if options.lcodes is True:
	if options.outputfile is not None:
		out = open(options.outputfile, 'w')
	for lang in langlist:
		for key in urld:
			if urld[key] == lang:
				if options.outputfile is not None:
					out.write(key + '\t' + urld[key] + '\t' + intd[key] + "\n")
				else:
					print (key, urld[key], intd[key], sep='\t')
	if options.outputfile is not None:	
		out.close()