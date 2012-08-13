#!/usr/bin/python

###	This script is part of the microblog-explorer project (https://github.com/adbar/microblog-explorer).
###	It is brought to you by Adrien Barbaresi.
###	It is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used with the output of a language identification system (https://github.com/saffsd/langid.py).


from collections import defaultdict

langd = defaultdict(int)
urld = defaultdict(int)

inp = raw_input('Languages wanted (comma-separated codes) : ')
langlist = inp.split(',')

f = open('sample', 'r')

for line in f:
	columns = line.split('\t')
	if len(columns) == 3:
		langd[columns[1]] += 1
		urld[columns[0]] = columns[1]

f.close()

for l in sorted(langd, key=langd.get, reverse=True):
	print l, langd[l]

out = open('sample-choice', 'w')

for lang in langlist:
	for key in urld:
		if urld[key] == lang:
			out.write(key + '\t' + urld[key] + '\n') 

out.close()
