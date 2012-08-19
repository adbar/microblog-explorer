#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


import re
import socket
from urllib2 import Request, urlopen, URLError
from StringIO import StringIO
import gzip
import time
import optparse
import sys

## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-s", "--starter", dest="starter", help="URL from where to start")
options, args = parser.parse_args()

if options.starter is None:
	parser.error('No start URL given')
match = re.match('^http://www.reddit.com/r/([A-Za-z0-9_-]+)/?', options.starter)
if match:
	starter = match.group(1)
	print "Starter:\t" + starter
else:
	sys.exit('The start URL does not seem to be valid')

## Initialization
timeout = 10
socket.setdefaulttimeout(timeout)

toofar = 0
initial = 1
extlinks = list()
intlinks = list()
userlinks = list()

# Select links
redint = re.compile(r'^http://www.reddit.com')
imgre = re.compile(r'\.jpg$|\.jpeg$|\.png')
imguryout = re.compile(r'imgur\.com/|youtube\.com/|youtu\.be|google')
reuser = re.compile(r'^http://www.reddit.com/user/([A-Za-z0-9_-]+)$')
#notintern = re.compile(r'/help/|/message/')

# Select next page
nextbefore = re.compile(r'^http://www.reddit.com/r/' + starter + '/\?[0-9a-z=]+&amp;')

next = re.compile(r'(http://www.reddit.com/r/' + starter + '/\?count=[0-9]+&amp;after=.+?)" rel="nofollow next"')

## Main loop
while toofar == 0:

	# Define request parameters
	if initial == 1:
		starter = starter.rstrip('/')
		req = Request('http://www.reddit.com/r/' + starter + '/') # all links available
		initial = 0
	else:
		time.sleep(3)
		nextpage = nextpage.replace('&amp;','&')
		print nextpage
		req = Request(nextpage)

	req.add_header('Accept-encoding', 'gzip')
	req.add_header('User-agent', 'Microblog-Explorer/0.1')

	# Load the page
	try:
		response = urlopen(req)
	except URLError, e:
		if hasattr(e, 'reason'):
			print 'We failed to reach a server.'
			print 'Reason: ', e.reason
		elif hasattr(e, 'code'):
			print 'The server couldn\'t fulfill the request.'
			print 'Error code: ', e.code

	if response.info().get('Content-Encoding') == 'gzip':
		buf = StringIO( response.read())
		gzf = gzip.GzipFile(fileobj=buf)
		htmlcode = gzf.read()
	elif response.info().gettype() == 'text/html':
		htmlcode = response.read()
	else:
		print 'no gzip or text/html content'

	# Find all interesting external links
	for link in re.findall(r'<a class="title " href="(http://.+?)"', htmlcode):
		match = redint.match(link)
		if match:
			intlinks.append(link)
		else:
			match1 = imguryout.search(link)
			if not match1:
				match2 = imgre.search(link)
				if not match2:
					extlinks.append(link)

	# Divide interesting internal links in 'users' and 'rest'
	for link in re.findall(r'<a href="(http://.+?)"', htmlcode):
		match1 = reuser.match(link)
		if match1:
			userlinks.append(match1.group(1))
		else:
			match2 = nextbefore.match(link)
			if not match2:
				intlinks.append(link)

	# Find the next page		
	match = next.search(htmlcode)
	if match:
		nextpage = match.group(1)
		nextpage = nextpage.replace('&amp;','&')
	else:
		toofar = 1

## End of main loop

extlinks = list(set(extlinks))
intlinks = list(set(intlinks))
userlinks = list(set(userlinks))

# Save lists to files
try:
	extout = open('external', 'w')
except IOError:
	print "could not open output file" # sys.exit
for link in extlinks:
	extout.write(link + "\n")
extout.close()

try:
	intout = open('internal', 'w')
except IOError:
	print "could not open output file"
for link in intlinks:
	intout.write(link + "\n")
intout.close()

try:
	userout = open('users', 'w')
except IOError:
	print "could not open output file"
for link in userlinks:
	userout.write(link + "\n")
userout.close()
