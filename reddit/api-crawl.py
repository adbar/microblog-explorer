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
import atexit

from enchant.checker import SpellChecker # see package 'python-enchant' on Debian/Ubuntu


## TODO:
# log file ?


## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-s", "--starter", dest="starter", help="URL from where to start")
parser.add_option("-l", "--language-code", dest="lcode", help="Language concerned")
parser.add_option("-u", "--users", dest="users", action="store_true", default=False, help="explore users pages")
parser.add_option("--no-language-check", dest="nolangcheck", action="store_true", default=False, help="disable the language check")
parser.add_option("-v", "--verbose", dest="verbose", action="store_true", default=False, help="debug mode")
parser.add_option("--path", dest="path", help="path to the files")
options, args = parser.parse_args()

# Parse languages requested
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
        'nl': 'nederlands+Vlaanderen', # +nl ?
        'no': 'norge+ektenyheter+oslo+norskenyheter',
        'po': 'Polska',
        'pt': 'portugal+brasil+BBrasil',
        'ro': 'Romania+cluj+Timisoara',
        'ru': 'ru',
        'sv': 'sweden+Gothenburg+umea',
        'tr': 'bloggerdal+gundem+teknoloji+kultur_sanat'
        }
        # Check if all the language codes are known
        if options.lcode in lcodes:
                starter = lcodes[options.lcode]
        else:
            print ('There is no source for this language code: ', options.lcode)
            print ('Currently supported language codes: ', sorted(lcodes.keys()))
            sys.exit()

# Sanity check for the starter
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

# set timeout
timelimit = 10
socket.setdefaulttimeout(timelimit)
# crawlers get banned below 2 seconds, see https://github.com/reddit/reddit/wiki/API
sleeptime = 2.1

toofar = 0
initial = 1
extlinks, userextlinks, intlinks, userlinks, suspicious = (set() for i in range(5))

# Configure spell check
#EngStopWords = set(["the", "and", "with", "a", "or", "here", "of", "for"])
spellcheck = SpellChecker("en_US")


## Regexes: select links
## General
# should be updated
extensions = re.compile(r'\.atom$|\.json$|\.css$|\.xml$|\.js$|\.jpg$|\.jpeg$|\.png$|\.gif$|\.tiff$|\.pdf$|\.ogg$|\.mp3$|\.m4a$|\.aac$|\.avi$|\.mp4$|\.mov$|\.webm$|\.flv$|\.ico$|\.pls$|\.zip$|\.tar$|\.gz$|\.iso$|\.swf$', re.IGNORECASE)
# unless ($1 =~ m/^[0-9]/) {) { ???
# should be updated
hostnames_filter = re.compile(r'last\.fm|soundcloud\.com|youtube\.com|youtu\.be|vimeo\.com|instagr\.am|instagram\.com|imgur\.com|flickr\.com|google\.|twitter\.com|twitpic\.com|gravatar\.com|akamai\.net|amazon\.com|cloudfront\.com', re.IGNORECASE)

## Reddit
reddit = re.compile(r'^http://www.reddit.com')
reuser = re.compile(r'^http://www.reddit.com/user/([A-Za-z0-9_-]+)$')
internlinks = re.compile(r'/help/|/message/|/comments/')
find_userids = re.compile(r'"author": "([A-Za-z0-9_-]+)",')
find_nextpage = re.compile(r'"id": "([a-z0-9]+)",')


####################         FUNCTIONS


# Fetch URL
def req(url):
    # start request
    req = Request(url)
    # headers
    req.add_header('Accept', 'application/json')
    req.add_header('Accept-Encoding', 'gzip')
    req.add_header('User-Agent', 'Microblog-Explorer/0.2 +https://github.com/adbar/microblog-explorer')

    try:
        # timeout: socket error
        response = urlopen(req, timeout = timelimit)
    except (URLError) as err:
        # log error message
        try:
            print ("Error: %r" % err, url)
        except NameError:
            print ('Error')
        return 'error'

    # adapt to content type
    if response.info().get('Content-Encoding') == 'gzip':
        buf = StringIO( response.read())
        gzf = gzip.GzipFile(fileobj=buf)
        jsoncode = gzf.read()
    elif response.info().gettype() == 'application/json':
        jsoncode = response.read()
    else:
        print ('no gzip or application/json content', response.info().gettype())
        return 'error'

    # sleep between two requests (very important)
    time.sleep(sleeptime)
    return jsoncode


# Find interesting external links
def findext(code):
    global extlinks, intlinks, suspicious, userextlinks
    if re.search(r'/user/', long_url):
        userlinks = 1
    else:
        userlinks = 0

    if options.nolangcheck is False:
        # find all 'title' elements to gather the texts of the links
        i = 0
        titles = re.findall(r'"title": "(.+?)",', code)

    # Find all URLs and filter them
    for link in re.findall(r'"url": "(http://.+?)",', code):
        # find and filter internal links
        if reddit.match(link):
            if not internlinks.search(link):
                intlinks.add(link)
        else:
            if not hostnames_filter.search(link):
                if not extensions.search(link):
                    if options.nolangcheck is False:
                        # Check spelling to see if the link text is in English
                        # strip punctuation
                        langtest = re.sub(r'[^\w\s]', '', titles[i]).rstrip()
                        # may be redundant, see enchant.tokenize
                        wordcount = len(re.findall(r'\w+', langtest))
                        errcount = 0
                        spellcheck.set_text(langtest)
                        for err in spellcheck:
                            errcount += 1
                        try:
                            # this may not be the optimal threshold
                            if ( (errcount/wordcount) > 0.33):
                                # add link to the respective set
                                if userlinks == 1:
                                    userextlinks.add(link)
                                else:
                                    extlinks.add(link)
                            else:
                                # add link to the rejected set
                                suspicious.add(link)
                        except ZeroDivisionError:
                            print ('empty title: ', titles[i])
                        i += 1
                    else:
                        # add link to the respective set
                        if userlinks == 1:
                            userextlinks.add(link)
                        else:
                            extlinks.add(link)

    return


# Save lists to files (function)
def writefile(filename, setname):
    if options.lcode is None:
        if options.starter is not None:
            filename = starter + '_' + filename
    else:
        filename = options.lcode + '_' + filename
    if options.path is not None:
        filename = options.path + filename
    try:
        out = open(filename, 'a')
    except IOError:
        sys.exit ("could not open output file")
    for link in setname:
        out.write(link + "\n")
    out.close()


### Exit strategy
# Write all files and logs
@atexit.register
def the_end():

    # Print summary
    print ('Links found on the subreddit page:\t', len(extlinks))
    print ('Users found:\t\t\t\t', len(userlinks))
    print ('Links found on user pages:\t\t', len(userextlinks))
    print ('Internal links:\t\t\t\t', len(intlinks))
    print ('Suspicious links (probably English):\t', len(suspicious))

    # append to files
    writefile('external', extlinks)
    writefile('extuserslinks', userextlinks)
    writefile('users', userlinks)
    writefile('internal', intlinks)
    writefile('suspicious', suspicious)

    print ('Execution time (secs): {0:.2f}' . format(time.time() - start_time))



####################         END OF FUNCTIONS


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
        if options.verbose is True:
            print (long_url)
        jsoncode = req(long_url)

    # Load the page
    if jsoncode == "error":
        print ("exiting loop, url:", long_url)
        break

    # Find all interesting external links
    findext(jsoncode)

    # Find all users
    for link in re.findall(find_userids, jsoncode):
        userlinks.add(link)

    # Find the next page
    ids = re.findall(find_nextpage, jsoncode)
    try:
        after = ids[-1]
    except IndexError:
        break

    toofar += 1

## End of main loop


## Begin user exploration if the 'users' switch is on

if options.users is True:
    controlvar = 1
    totusers = len(userlinks)

    # users loop
    for userid in userlinks:
        if options.verbose is True:
            print ('user', controlvar, '/', totusers, sep=' ')
        toofar = 0
        initial = 1

        # Reddit does not allow queries beyond 5 pages back
        while toofar < 5:
            if initial == 1:
                long_url = 'http://www.reddit.com/user/' + userid + '/submitted.json?sort=new&limit=100'
                jsoncode = req(long_url)
                initial = 0
            else:
                long_url = 'http://www.reddit.com/user/' + userid + '/submitted.json?sort=new&limit=100&after=t3_' + after
                if options.verbose is True:
                    print (long_url)
                jsoncode = req(long_url)

            # Load the page
            if jsoncode == "error":
                print ("exiting loop, url:", long_url)
                break

            # Find all interesting external links
            findext(jsoncode)

            # Find the next page
            ids = re.findall(find_nextpage, jsoncode)
            try:
                after = ids[-1]
            except IndexError:
                break

            toofar += 1

        # end of users loop:
        controlvar += 1
