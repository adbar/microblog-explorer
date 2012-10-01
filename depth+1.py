#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


from __future__ import print_function
from __future__ import division
import re
import socket
from urllib2 import Request, urlopen, URLError, quote, unquote
from StringIO import StringIO
import gzip
import time
import optparse
from urlparse import urlparse
import signal
import sys
from random import choice
import atexit


## TODO
# interesting tld-extractor : https://github.com/john-kurkowski/tldextract


# Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-i", "--input-file", dest="inputfile", help="input file name", metavar="FILE")
parser.add_option("-o", "--output-file", dest="outputfile", help="output file name", metavar="FILE")
parser.add_option("-s", "--sampling", dest="sampling", action="store_true", default=False, help="URL sampling to save time")
parser.add_option("-t", "--timeout", dest="timeout", help="timeout for requests (in sec, default 10)")

options, args = parser.parse_args()

if options.inputfile is None:
	parser.error('No input file given, I need fresh urls (-h or --help for more information)')
if options.outputfile is None:
	parser.error('No output file given, things could get a little bit messy if I print thousands of URLs to standard output (-h or --help for more information)')
if options.timeout is None:
	options.timeout = 10


# Initialize
options.timeout = int(options.timeout)
alarm_timeout = 20 + options.timeout
# socket.setdefaulttimeout(timeout) ??
urls, sampled_urls, newurls = ([] for i in range(3))

# avoid getting trapped
mediafinal = re.compile(r'\.jpg$|\.jpeg$|\.png$|\.gif$|\.pdf$|\.ogg$|\.mp3$|\.avi$|\.mp4$', re.IGNORECASE)
mediaquery = re.compile(r'\.jpg[&?]|\.jpeg[&?]|\.png[&?]|\.gif[&?]|\.pdf[&?]|\.ogg[&?]|\.mp3[&?]|\.avi[&?]|\.mp4[&?]', re.IGNORECASE)


## Open and read URL source file
try:
	sourcefile = open(options.inputfile, 'r')
except IOError:
	sys.exit("could not open the file containing the urls")

# time the whole script
start_time = time.time()

for line in sourcefile:
	line = line.rstrip('\n')
	line = line.rstrip('/')
        if not mediafinal.search(line) and not mediaquery.search(line):
		urls.append(line)
sourcefile.close()

urls = list(set(urls))


# url sampling to spare time
def sampling(urls):
	temp = list()
	sampled_urls = list()
	last = ''
	lasturl = ''
	urls = sorted(urls, key=str.lower)
	for link in urls:
		hostname = urlparse(link).netloc
                if hostname is last:
			temp.append(link)
		else:
			if temp:
				sampled_urls.append(choice(temp))
			else:
				sampled_urls.append(lasturl)
			last = hostname
			lasturl = link
			temp = list()
	return sampled_urls


if options.sampling is True:
	print ('Raw urls:', len(urls))
	urls = sampling(urls)
	print ('Sampled urls:', len(urls))


# fetch URL
def req(url):
	req = Request(url)
	req.add_header('Accept-encoding', 'gzip')
	req.add_header('User-agent', 'Microblog-Explorer/0.2')

	try:
		response = urlopen(req, timeout = options.timeout)
	except Exception as e:
		if hasattr(e, 'reason'):
			print (e.reason, ':', url)
		else:
			print ("Unclassified error: %r" % e, url)
        	return 'error'

	size = response.info().get('Content-Length')
	if size:
		size = int(size)
	if size < 1000000 or not size:
		if response.info().get('Content-Encoding') == 'gzip':
			try:
				buf = StringIO( response.read())
				gzf = gzip.GzipFile(fileobj=buf)
				htmlcode = gzf.read()
			except Exception as e:
				if hasattr(e, 'reason'):
					print (e.reason, ':', url)
				else:
					print ("Unclassified error: %r" % e, url)
				return 'error'
		elif response.info().gettype() == 'text/html':
			try:
				htmlcode = response.read()
			except Exception as e:
				if hasattr(e, 'reason'):
					print (e.reason, ':', url)
				else:
					print ("Unclassified error: %r" % e)
				return 'error'
		else:
			print ('no gzip or text/html content: ', url)
			return 'error'
	else:
		print ('content-length to high (', size, '): ', url)
		return 'error'

	return htmlcode


# Extract links
def findlinks(code):
	pageurls = list()
	# better than a regex : lxml ?
	##from lxml.html import parse
	##dom = parse('http://www.google.com/').getroot()
	##links = dom.cssselect('a')
	for candidate in re.findall(r'href="(http://.+?)"', code):
		if not mediafinal.search(candidate) and not mediaquery.search(candidate):
			try:
				# useful out of western domain names
				candidate = unquote(quote(candidate.encode("utf8"))).decode("utf8")
			except UnicodeDecodeError:
				pass
			else:
				pageurls.append(candidate.rstrip('/'))
	
	pageurls = list(set(pageurls))
	return pageurls


# Append to a file
## lock the file ?
def writefile(filename, listname):
	#filename = options.lcode + '_' + filename
	try:
		out = open(filename, 'a')
	except IOError:
		sys.exit ("could not open output file")
	for link in listname:
		out.write(link + "\n")
	out.close()


# Handle SIGALRM
def handler(signum, frame):
    print ('Signal handler called with signal ', signum)
    raise RuntimeError("Crawler blocked")


# links counter
counter = 0
errors_counter = 0

# MAIN LOOP
for link in urls:
	counter += 1

	try:
		# alarm
		signal.signal(signal.SIGALRM, handler)
		signal.alarm(alarm_timeout)
		# fetch page and extract links
		htmlcode = req(link)
		if htmlcode:
			if htmlcode is 'error':
				errors_counter += 1
				signal.alarm(0)
				continue
			pageurls = findlinks(htmlcode)
			newurls.extend(pageurls)
	except RuntimeError: # one way to catch it...
		print ('Crawler blocked, exiting page: ', link)

	signal.alarm(0)

	#if counter % 10 == 0: # may not be necessary
	newurls = list(set(newurls)) # is it fast enough ?

	# write to a file before filling the RAM with urls
	if len(newurls) > 5000:
		writefile(options.outputfile, newurls)
		newurls = list()


# Write everything needed, even if there was an exception
@atexit.register
def the_end():
	print ('Number of links analyzed :', counter)
	print ('Total links in the list :', len(urls))
	print ('Number of errors :', errors_counter)
	newurls = list(set(newurls))
	writefile(options.outputfile, newurls)
	print ('Execution time (secs): {0:.2f}' . format(time.time() - start_time))
