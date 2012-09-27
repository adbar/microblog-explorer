#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

### The official API module for Python is much more complete : https://code.google.com/p/friendfeed-api/


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
import codecs
from urlparse import urlparse

from enchant.checker import SpellChecker # see package 'python-enchant' on Debian/Ubuntu
spellcheck = SpellChecker("en_US")
langcheck = 0

from collections import defaultdict
bodies = defaultdict(int)


# TODO:
# number of requests
# blogspot filter ?
# interesting tld-extractor : https://github.com/john-kurkowski/tldextract
# timeout
# reduce code ('sleep' in 'fetch', concats, functions)
# todo/done ?


## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-s", "--simple", dest="simple", action="store_true", default=False, help="simple crawl ONLY (just the public feed)")
parser.add_option("-u", "--users", dest="users", action="store_true", default=False, help="users crawl ONLY (without public feed)")
parser.add_option("-f", "--friends", dest="friends", action="store_true", default=False, help="friends crawl")
parser.add_option("-d", "--deep", dest="deep", action="store_true", default=False, help="smart deep crawl")
# parser.add_option("-r", "--requests", dest="requests", help="max requests")
options, args = parser.parse_args()


# nothing indicated in the API documentation : http://friendfeed.com/api/documentation
# 2 secs seem to be close to the limit though
sleeptime = 2.25
timelimit = 12
total_requests = 0

## FILTERS
# comments
reject = re.compile(r'"[0-9]+ comments?"')
# spam (small list, to be updated)
spam = re.compile(r'viagra|^fwd|gambling|casino|loans|cialis|price|shop', re.IGNORECASE) # also in urls ?
# internal links (no used)
interntest = re.compile(r'http://friendfeed.com/')

userstodo = list()
links = list()
rejectlist = list()

try:
    usersfile = open('users', 'r')
    usersdone = usersfile.readlines()
    usersfile.close()
except IOError:
    if options.users is True:
        sys.exit('"users" file mandatory with the -u/--users switch')
    else:
        usersdone = list()


# time the whole script
start_time = time.time()



### SUBS

# write files
def writefile(filename, listname):
    #filename = options.lcode + '_' + filename
    try:
        out = open(filename, 'a')
    except IOError:
        sys.exit ("could not open output file")
    for link in listname:
        out.write(link + "\n")
    out.close()

# Fetch URL
def req(url):
    global total_requests
    total_requests += 1
    req = Request(url)
    req.add_header('Accept-encoding', 'gzip')
    req.add_header('User-agent', 'Microblog-Explorer/0.2')

    try:
        response = urlopen(req, timeout = timelimit)
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
        print ('no gzip or application/json content:', url)
        return 'error'
    
    #jsoncode = jsoncode.decode('utf-8', 'replace')
    #jsoncode = unicode(jsoncode.strip(codecs.BOM_UTF8), 'utf-8')

    return jsoncode



# Find interesting external links
def findlinks(code, step):
    sublinks = list()
    chunks = re.findall(r'{"type":".+?","id":"(.+?)","name":".+?"}', code)
    chunknum = 0
    titles = re.findall(r',{?"body":"(.+?)",', code)

    for body in titles:
        flag = 0
        body = body.rstrip()
        commentsre = reject.search(body)
        spamre = spam.search(body)
        if not commentsre and not spamre:
            urlre = re.search(r'href=\\"(http://.+?)\\"', body)
            if urlre:
                url = urlre.group(1)
                body = re.sub('<.+?>.+?</.+?>', '', body)
                body = re.sub(' - $', '', body)
                if not body in bodies and len(body) > 15: # split these conditions ?
                    bodies[body] = 1
                    internre = interntest.search(url)
                    if internre:
                        pass # TODO
                    else:
                        # Check spelling to see if the link text is in English
                        wordcount = len(re.findall(r'\w+', body)) # redundant, see enchant.tokenize
                        errcount = 0
                        try :
                            spellcheck.set_text(body)
                            for err in spellcheck:
                                errcount += 1
                            try:
                                if ( (errcount/wordcount) > 0.5):
                                    flag = 1
                                else:
                                    rejectlist.append(url)
                            except ZeroDivisionError:
                                print ("empty title:", body)
                                #i += 1
                        except (UnicodeEncodeError, AttributeError):
                            flag = 1

                else:			# body in bodies
                    bodies[body] += 1	#frequent posts detection and storage

        if flag == 1:
            # find the user behind the tweet
            if step == 1:
                try:
                    chunks[chunknum] = re.sub('".+?$', '', chunks[chunknum])
                    if chunks[chunknum] not in usersdone: #and not in userstodo:
                        userstodo.append(chunks[chunknum])
                except IndexError:
                    pass

            # Google News etc. URL filter
            urlre = re.search(r'q=(http.+?)&amp', url)
            if urlre:
                url = urlre.group(1)
            urlre = re.search(r'url=(http.+?)&?', url)
            if urlre:
                url = urlre.group(1)

            if len(url) > 10:
                sublinks.append(url)

        chunknum += 1
    sublinks = list(set(sublinks))
    return sublinks


# First pass : crawl of the homepage (public feed), can be skipped with the -u/--users switch
if options.users is False:
    jsoncode = req('http://friendfeed-api.com/v2/feed/public?maxcomments=0&maxlikes=0&num=100')
    #jsoncode = (jsoncode.decode('utf-8')).encode('utf8')

    templinks = findlinks(jsoncode, 1)
    links.extend(templinks)

# Possible second loop : go see the users on the list (and eventually their friends)

if options.simple is False:

    userstodo = list(set(userstodo))
    links = list(set(links))
    rejectlist = list(set(rejectlist))

    for userid in userstodo:
        time.sleep(sleeptime)
        jsoncode = req('http://friendfeed-api.com/v2/feed/' + userid + '?maxcomments=0&maxlikes=0&num=100')
        if jsoncode is not 'error':
            templinks = findlinks(jsoncode, 2)
            links.extend(templinks)
            # smart deep crawl
            if options.deep is True:
                hostnames = defaultdict(int)
                for link in templinks:
                    hostname = urlparse(link).netloc
                    hostnames[hostname] += 1
                try:
                    ratio = len(templinks)/len(hostnames)
                    if ratio >= 5: # could also be 7 or 10
                        print (ratio)
                        time.sleep(sleeptime)
                        jsoncode = req('http://friendfeed-api.com/v2/feed/' + userid + '?maxcomments=0&maxlikes=0&start=100&num=100')
                        if jsoncode is not 'error':
                            templinks = findlinks(jsoncode, 2)
                            links.extend(templinks)
                except ZeroDivisionError:
                    pass
                
            #usersdone.append(userid)

	# crawl the 'friends' page
        if options.friends is True:
            time.sleep(sleeptime)
            jsoncode = req('http://friendfeed-api.com/v2/feed/' + userid + '/friends?maxcomments=0&maxlikes=0&num=100')
            if jsoncode is not 'error':
                templinks = findlinks(jsoncode, 1)
                links.extend(templinks)
                # smart deep crawl
                if options.deep is True:
                    hostnames = defaultdict(int)
                    for link in templinks:
                        hostname = urlparse(link).netloc
                        hostnames[hostname] += 1
                    try:
                        ratio = len(templinks)/len(hostnames)
                        if ratio >= 5: # could also be 7 or 10
                            print (ratio)
                            time.sleep(sleeptime)
                            jsoncode = req('http://friendfeed-api.com/v2/feed/' + userid + '?maxcomments=0&maxlikes=0&start=100&num=100')
                            if jsoncode is not 'error':
                                templinks = findlinks(jsoncode, 2)
                                links.extend(templinks)
                    except ZeroDivisionError:
                        pass


# Write all the logs and files
print ('Requests:\t', total_requests)
userstodo = list(set(userstodo))
print ('New users:\t', len(userstodo))
writefile('users', userstodo)
rejectlist = list(set(rejectlist))
print ('Rejected:\t', len(rejectlist))
writefile('rejected', rejectlist)
links = list(set(links))
print ('Links:\t\t', len(links))
writefile('links', links)

print ('Execution time (secs): {0:.2f}' . format(time.time() - start_time))