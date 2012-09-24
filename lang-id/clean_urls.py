#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


import re
import optparse
import sys

# TODO:
## split lines of the kind '.htmlhttp://'


# Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-i", "--input-file", dest="inputfile",
	help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile",
	help="output file name", metavar="FILE")

options, args = parser.parse_args()

if options.inputfile is None or options.outputfile is None:
	parser.error('input AND output file mandatory (-h or --help for more information)')


# Main regexes
protocol = re.compile(r'^http')
notsuited = re.compile(r'^http://add?\.|^http://banner\.|feed$')
mediafinal = re.compile(r'\.jpg$|\.jpeg$|\.png$|\.gif$|\.pdf$|\.ogg$|\.mp3$|\.avi$|\.mp4$|\.css$', re.IGNORECASE)
mediaquery1 = re.compile(r'\.jpg\?|\.jpeg\?|\.png\?|\.gif\?|\.pdf\?|\.ogg\?|\.mp3\?|\.avi\?|\.mp4\?', re.IGNORECASE)
mediaquery2 = re.compile(r'\.jpg&|\.jpeg&|\.png&|\.gif&|\.pdf&|\.ogg&|\.mp3&|\.avi&|\.mp4&', re.IGNORECASE) 



# Open source and destination files
try:
	sourcefile = open(options.inputfile, 'r')
except IOError:
	sys.exit("could not open the input file")
try:
	destfile = open(options.outputfile, 'w')
except IOError:
	sys.exit("could not open or write to the output file")

# MAIN LOOP
for candidate in sourcefile:
	candidate = candidate.rstrip()
	# regexes tests : a bit heavy...
	match1 = protocol.search(candidate)
	if match1 and len(candidate) > 10:
		match2 = mediafinal.search(candidate)
		if not match2:
			match3 = notsuited.search(candidate)
			if not match3:
				match4 = mediaquery1.search(candidate)
				match5 = mediaquery2.search(candidate)
				if not match4 and not match5:
					destfile.write(candidate + "\n")

sourcefile.close()
destfile.close()
