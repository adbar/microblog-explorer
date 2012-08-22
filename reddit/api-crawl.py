#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


from __future__ import print_function
from __future__ import division
import re
import socket
from urllib2 import Request, urlopen, URLError
from StringIO import StringIO
import gzip
import time
import optparse
import sys

from enchant.checker import SpellChecker # see package 'python-enchant' on Debian/Ubuntu


## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-s", "--starter", dest="starter", help="URL from where to start")
parser.add_option("-l", "--language-code", dest="lcode", help="Language concerned")
options, args = parser.parse_args()

if options.starter is None:
	if options.lcode is None:
		parser.error('No start URL and no start language given')
	else:
		lcodes = {
		'cs': 'cesky',
		'da': 'dkpol+denmark',
		'de': 'de+deutschland+germany+austria+switzerland+piratenpartei+hamburg+berlin+frankfurt+munich+freiburg+wiesbaden+datenschutz+de_it+fragreddit+teutonik+germusic+germanyusa+GermanPractice+cologne+Dokumentationen+fernsehen+hoerbuecher+niedersachsen+schleswigholstein',
		'es': 'redditores+espanol+programacion+peru+mexico+latinoamerica+es+colombia+chile+argentina+uruguay+ecuador+bolivia+paraguay+venezuela+Guatemala+elsalvador+Cinefilos+futbol+role+djangoes+practicar+videojuego',
		'fi': 'suomi+EiOleLehti',
		'fr': 'Quebec+france',
		'it': 'italy',
		'no': 'norge+ektenyheter+oslo',
		'po': 'Polska',
		'pt': 'portugal+brasil+BBrasil',
		'ro': 'Romania+cluj+Timisoara'
		}
		if options.lcode in lcodes:
    			starter = lcodes[options.lcode]
		else:
			print ('There is no source for this language code: ', options.lcode)
			print ('Currently supported language codes: ', sorted(lcodes.keys()))
			sys.exit()

else:
	match = re.match('^http://www.reddit.com/r/([A-Za-z0-9/_+-]+)', options.starter)
	if match:
		starter = match.group(1)
	else:
		match1 = re.match('^([A-Za-z0-9/_+-]+)$', options.starter)
		if match1:
			starter = match1.group(1)
		else:
			sys.exit('The start URL does not seem to be valid')


## Initialization
print ("Starter:\t", starter)
timeout = 10
socket.setdefaulttimeout(timeout)
sleeptime = 2.1 # crawlers get banned below 2 seconds, see https://github.com/reddit/reddit/wiki/API

toofar = 0
initial = 1
extlinks = list()
userextlinks = list()
intlinks = list()
userlinks = list()
suspicious = list()
temp1 = list()
temp2 = list()
temp3 = list()

#EngStopWords = set(["the", "and", "with", "a", "or", "here", "of", "for"])
spellcheck = SpellChecker("en_US")
langcheck = 0


# Select links
redint = re.compile(r'^http://www.reddit.com')
mediare = re.compile(r'\.jpg$|\.JPG$|\.jpeg$|\.png$|\.gif$|\.ogg$|\.mp3$|\.avi$|\.mp4$')
imguryout = re.compile(r'imgur\.com/|youtube\.com/|youtu\.be|google')
reuser = re.compile(r'^http://www.reddit.com/user/([A-Za-z0-9_-]+)$')
notintern = re.compile(r'/help/|/message/|/comments/')


## Functions

# Fetch URL
def req(url):
	req = Request(url)
	req.add_header('Accept-encoding', 'gzip')
	req.add_header('User-agent', 'Microblog-Explorer/0.1')

	try:
		response = urlopen(req)
	except URLError, e:
		if hasattr(e, 'reason'):
			print ('Failed to reach server.')
			print ('Reason: ', e.reason)
		elif hasattr(e, 'code'):
			print ('The server couldn\'t fulfill the request.')
			print ('Error code: ', e.code)
		return "error"

	if response.info().get('Content-Encoding') == 'gzip':
		buf = StringIO( response.read())
		gzf = gzip.GzipFile(fileobj=buf)
		jsoncode = gzf.read()
	elif response.info().gettype() == 'application/json':
		jsoncode = response.read()
	else:
		print ('no gzip or application/json content')
		return "error"
	
	return jsoncode

# For next urls (i.e. not the first one)
def newreq(url):
	time.sleep(sleeptime)
	print (url)
	code = req(url)
	return code

# Find interesting external links
def findext(code):
	extl = list()
	intl = list()
	rejl = list()
	if langcheck == 1:
		i = 0
		titles = re.findall(r'"title": "(.+?)",', code)
	for link in re.findall(r'"url": "(http://.+?)",', code):
		match = redint.match(link)
		if match:
			match1 = notintern.search(link)
			if not match1:
				intl.append(link)
		else:
			match1 = imguryout.search(link)
			if not match1:
				match2 = mediare.search(link)
				if not match2:
					if langcheck == 1:
						# Check spelling to see if the link text is in English
						wordcount = len(re.findall(r'\w+', titles[i])) # redundant, see enchant.tokenize
						errcount = 0
						spellcheck.set_text(titles[i])
						for err in spellcheck:
							errcount += 1
						try:
							if ( (errcount/wordcount) > 0.33):
								extl.append(link)
							else:
								rejl.append(link)
						except ZeroDivisionError:
							print ("empty title: ", titles[i])
						i += 1
					else:
						extl.append(link)
	return (extl, intl, rejl)


## Main loop
while toofar < 5:

	# Define request parameters
	if initial == 1:
		starter = starter.rstrip('/')
		jsoncode = req('http://www.reddit.com/r/' + starter + '/new/.json?sort=new&limit=100')
		initial = 0
	else:
		jsoncode = newreq('http://www.reddit.com/r/' + starter + '/new/.json?sort=new&limit=100&after=t3_' + after)

	# Load the page
	if jsoncode == "error":
		print ("exiting loop")
		break

	# Find all interesting external links
	(temp1, temp2, temp3) = findext(jsoncode)
	extlinks.extend(temp1)
	intlinks.extend(temp2)
	suspicious.extend(temp3)

	# Find all users
	for link in re.findall(r'"author": "([A-Za-z0-9_-]+)",', jsoncode):
		userlinks.append(link)

	# Find the next page
	ids = re.findall(r'"id": "([a-z0-9]+)",', jsoncode)
	try:
		after = ids[-1]
	except IndexError:
		break

	toofar += 1

## End of main loop

extlinks = list(set(extlinks))
intlinks = list(set(intlinks))
userlinks = list(set(userlinks))


## Begin user exploration

controlvar = 1
langcheck = 1
totusers = len(userlinks)

for userid in userlinks:
	print ('user', controlvar, '/', totusers, sep=' ')
	toofar = 0
	initial = 1
	while toofar < 5:
		if initial == 1:
			jsoncode = newreq('http://www.reddit.com/user/' + userid + '/submitted.json?sort=new&limit=100')
			initial = 0
		else:
			jsoncode = newreq('http://www.reddit.com/user/' + userid + '/submitted.json?sort=new&limit=100&after=t3_' + after)

		# Load the page
		if jsoncode == "error":
			print ("exiting loop")
			break

		# Find all interesting external links
		(temp1, temp2, temp3) = findext(jsoncode)
		userextlinks.extend(temp1)
		intlinks.extend(temp2)
		suspicious.extend(temp3)

		# Find the next page
		ids = re.findall(r'"id": "([a-z0-9]+)",', jsoncode)
		try:
			after = ids[-1]
		except IndexError:
			break

		toofar += 1
	controlvar += 1
	if controlvar % 10 == 0:
		extlinks = list(set(extlinks))
		intlinks = list(set(intlinks))


extlinks = list(set(extlinks))
print ('Links found on the subreddit page:\t', len(extlinks))
userlinks = list(set(userlinks))
print ('Users found:\t\t\t\t', len(intlinks))
userextlinks = list(set(userextlinks))
print ('Links found on user pages:\t\t', len(userextlinks))
intlinks = list(set(intlinks))
print ('Internal links:\t', len(intlinks))
suspicious = list(set(suspicious))
print ('Suspicious links (probably English):\t', len(suspicious))

# Save lists to files

def writefile(filename, listname):
	filename = options.lcode + '_' + filename
	try:
		out = open(filename, 'a')
	except IOError:
		sys.exit ("could not open output file")
	for link in listname:
		out.write(link + "\n")
	out.close()

writefile('external', extlinks)
writefile('extuserslinks', userextlinks)
writefile('users', userlinks)
writefile('internal', intlinks)
writefile('suspicious', suspicious)