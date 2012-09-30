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
parser.add_option("-u", "--users", dest="users", action="store_true", default=False, help="explore users pages")
parser.add_option("--no-language-check", dest="nolangcheck", action="store_true", default=False, help="disable the language check")
parser.add_option("-v", "--verbose", dest="verbose", action="store_true", default=False, help="debug mode")
options, args = parser.parse_args()

if options.starter is None:
	if options.lcode is None:
		parser.error('No start URL and no start language given')
	else:
		lcodes = {
		'cs': 'cesky',
		'da': 'dkpol+denmark+aarhus',
		'de': 'de+deutschland+austria+piratenpartei+wiesbaden+datenschutz+de_it+teutonik+fernsehen',
		'es': 'redditores+espanol+programacion+peru+mexico+latinoamerica+es+colombia+chile+argentina+uruguay+ecuador+bolivia+paraguay+venezuela+Guatemala+elsalvador+Cinefilos+futbol+role+djangoes+practicar+videojuego',
		'fi': 'suomi+EiOleLehti',
		'fr': 'Quebec+france',
		'hi': 'Hindi',
		'hr': 'croatia',
		'it': 'italy',
		'no': 'norge+ektenyheter+oslo+norskenyheter',
		'po': 'Polska',
		'pt': 'portugal+brasil+BBrasil',
		'ro': 'Romania+cluj+Timisoara',
		'ru': 'ru',
		'sv': 'sweden+Gothenburg+umea'
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


## INITIALIZE

# time the whole script
start_time = time.time()

if options.verbose is True:
	print ("Starter:\t", starter)

timeout = 10
socket.setdefaulttimeout(timeout)
# crawlers get banned below 2 seconds, see https://github.com/reddit/reddit/wiki/API
sleeptime = 2.1

toofar = 0
initial = 1
extlinks, userextlinks, intlinks, userlinks, suspicious, temp1, temp2, temp3 = ([] for i in range(8))

#EngStopWords = set(["the", "and", "with", "a", "or", "here", "of", "for"])
spellcheck = SpellChecker("en_US")


# Select links
reddit = re.compile(r'^http://www.reddit.com')
mediare = re.compile(r'\.jpg$|\.jpeg$|\.png$|\.gif$|\.pdf$|\.ogg$|\.mp3$|\.avi$|\.mp4$', re.IGNORECASE)
hostnames_filter = re.compile(r'last\.fm|youtube\.com|youtu\.be|flickr\.com|vimeo\.com|instagr\.am|imgur\.com/|google\.', re.IGNORECASE)
reuser = re.compile(r'^http://www.reddit.com/user/([A-Za-z0-9_-]+)$')
internlinks = re.compile(r'/help/|/message/|/comments/')


####################	 	FUNCTIONS


# Fetch URL
def req(url):
	req = Request(url)
	req.add_header('Accept-encoding', 'gzip')
	req.add_header('User-agent', 'Microblog-Explorer/0.2')

	try:
        	response = urlopen(req)
	except (URLError) as e:
        	try:
			print ("Error: %r" % e, url)
		except NameError:
			print ('Error')
		return 'error'

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
	if options.verbose is True:
		print (url)
	code = req(url)
	return code


# Find interesting external links
def findext(code):
	extl, intl, rejl = ([] for i in range(3))

	if options.nolangcheck is False:
		# find all 'title' elements to gather the texts of the links
		i = 0
		titles = re.findall(r'"title": "(.+?)",', code)

	# Find all URLs and filter them
	for link in re.findall(r'"url": "(http://.+?)",', code):
		if reddit.match(link):
			if not internlinks.search(link):
				intl.append(link)
		else:
			if not hostnames_filter.search(link):
				if not mediare.search(link):
					if options.nolangcheck is False:
						# Check spelling to see if the link text is in English
						# strip punctuation
						langtest = re.sub(r'\p{P}+', '', titles[i])
						# may be redundant, see enchant.tokenize
						wordcount = len(re.findall(r'\w+', langtest))
						errcount = 0
						spellcheck.set_text(langtest)
						for err in spellcheck:
							errcount += 1
						try:
							# this may be either too high or incorrect
							if ( (errcount/wordcount) > 0.33):
								extl.append(link)
							else:
								rejl.append(link)
						except ZeroDivisionError:
							print ('empty title: ', titles[i])
						i += 1
					else:
						extl.append(link)
	return (extl, intl, rejl)


####################	 	END OF FUNCTIONS


## Main loop

# Reddit does not allow queries beyond 5 pages back
while toofar < 5:

	# Define request parameters
	if initial == 1:
		starter = starter.rstrip('/')
		long_url = 'http://www.reddit.com/r/' + starter + '/new/.json?sort=new&limit=100'
		jsoncode = req(long_url)
		initial = 0
	else:
		long_url = 'http://www.reddit.com/r/' + starter + '/new/.json?sort=new&limit=100&after=t3_' + after
		jsoncode = newreq(long_url)

	# Load the page
	if jsoncode == "error":
		print ("exiting loop, url:", long_url)
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


## Begin user exploration if the 'users' switch is on

if options.users is True:
	extlinks = list(set(extlinks))
	intlinks = list(set(intlinks))
	userlinks = list(set(userlinks))
	controlvar = 1
	totusers = len(userlinks)

	for userid in userlinks:
		if options.verbose is True:
			print ('user', controlvar, '/', totusers, sep=' ')
		toofar = 0
		initial = 1

		# Reddit does not allow queries beyond 5 pages back
		while toofar < 5:
			if initial == 1:
				long_url = 'http://www.reddit.com/user/' + userid + '/submitted.json?sort=new&limit=100'
				jsoncode = newreq(long_url)
				initial = 0
			else:
				long_url = 'http://www.reddit.com/user/' + userid + '/submitted.json?sort=new&limit=100&after=t3_' + after
				jsoncode = newreq(long_url)

			# Load the page
			if jsoncode == "error":
				print ("exiting loop, url:", long_url)
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



# Uniq the lists and show useful data
extlinks = list(set(extlinks))
print ('Links found on the subreddit page:\t', len(extlinks))
userlinks = list(set(userlinks))
print ('Users found:\t\t\t\t', len(intlinks))
userextlinks = list(set(userextlinks))
print ('Links found on user pages:\t\t', len(userextlinks))
intlinks = list(set(intlinks))
print ('Internal links:\t\t\t\t', len(intlinks))
suspicious = list(set(suspicious))
print ('Suspicious links (probably English):\t', len(suspicious))


# Save lists to files

# function
def writefile(filename, listname):
	if options.lcode is None:
		if options.starter is not None:
			filename = starter + '_' + filename
	else:
		filename = options.lcode + '_' + filename
	try:
		out = open(filename, 'a')
	except IOError:
		sys.exit ("could not open output file")
	for link in listname:
		out.write(link + "\n")
	out.close()

# uses of the function
writefile('external', extlinks)
writefile('extuserslinks', userextlinks)
writefile('users', userlinks)
writefile('internal', intlinks)
writefile('suspicious', suspicious)

print ('Execution time (secs): {0:.2f}' . format(time.time() - start_time))