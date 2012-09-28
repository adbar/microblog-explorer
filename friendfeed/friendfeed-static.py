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
import atexit
import os

from enchant.checker import SpellChecker # see package 'python-enchant' on Debian/Ubuntu
spellcheck = SpellChecker("en_US")
langcheck = 0

from collections import defaultdict
bodies = defaultdict(int)


# TODO:
# interesting tld-extractor : https://github.com/john-kurkowski/tldextract
# reduce code (concats, functions)
# todo/done ?
# internal links
# continue / break ?
# comments : program structure
# -df bug ?


## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-s", "--simple", dest="simple", action="store_true", default=False, help="simple crawl ONLY (just the public feed)")
parser.add_option("-u", "--users", dest="users", action="store_true", default=False, help="users crawl ONLY (without public feed)")
parser.add_option("-f", "--friends", dest="friends", action="store_true", default=False, help="friends crawl")
parser.add_option("-d", "--deep", dest="deep", action="store_true", default=False, help="smart deep crawl")
parser.add_option("-r", "--requests", dest="requests", help="max requests")
parser.add_option("-v", "--verbose", dest="verbose", action="store_true", default=False, help="debug mode (body and ids info)")
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
spam = re.compile(r'viagra|^fwd|gambling|casino|loans|cialis|price|shop|buyonlinetab|buytabonline|streaming', re.IGNORECASE) # also in urls ?
# internal links (no used)
interntest = re.compile(r'http://friendfeed.com/')


usersdone, userstodo, links, rejectlist, templinks = ([] for i in range(5))


try:
    usersfile = open('users', 'r')
    usersdone = usersfile.readlines()
    usersfile.close()
except IOError:
    if options.users is True:
        #sys.exit('"users" file mandatory with the -u/--users switch')
        print ('"users" file mandatory with the -u/--users switch')
        os._exit(1)
    else:
        pass


# time the whole script
start_time = time.time()


### SUBS


# write/append to files
def writefile(filename, listname, mode):
    #filename = options.lcode + '_' + filename
    try:
        out = open(filename, mode)
    except IOError:
        sys.exit ("could not open output file")
    for link in listname:
        out.write(str(link) + "\n")
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

    if options.simple is False:
        time.sleep(sleeptime)

    return jsoncode


# Find interesting external links
def findlinks(code, step):
    sublinks = list()
    subdict = defaultdict(int)
    testlist = list()

    ## 'If I strip everything I don't want, I'll be able to fetch what I want'...
    ## To be replaced by a proper parser ?
    code = re.sub(r'^.+?\[', '', code)
    code = re.sub(r'"comments":\[.+?\],', '', code)
    code = re.sub(r'"thumbnails":\[.+?\],', '', code)
    code = re.sub(r'"likes":\[.+?\],', '', code)
    if step != 2:
        code = re.sub(r'"to":\[.+?\],', '', code) # could be useful
        code = re.sub(r'"via":{.+?},', '', code)
        code = re.sub(r'"url":".+?",', '', code)
        code = re.sub(r'"date":".+?",', '', code)
        if step == 3:
            code = re.sub(r'"id":"e/.+?"', '', code)
        else:
            code = re.sub(r'"id":"e/.+?",', '', code)
        code = re.sub(r'"from":{"type":".+?",', '', code)
        code = re.sub(r'"name":".+?"', '', code)

    if step == 1 or step == 3:
        bodylist = re.findall(r'{"body":".+?","id":".+?",}', code)
    elif step == 2:
        bodylist = re.findall(r'{"body":".+?",', code)
    for item in bodylist:
        if step == 1 or step == 3:
            bodyre = re.search(r'{"body":"(.+?)","id":"(.+?)",}', item)
            subdict[bodyre.group(1)] = bodyre.group(2)
        elif step == 2:
            bodyre = re.search(r'{"body":"(.+?)",', item)
            subdict[bodyre.group(1)] += 1

    for body in subdict.keys():
        flag = 0
        marker = body
        body = body.rstrip()

        # check for spam and reject
        commentsre = reject.search(body)
        spamre = spam.search(body)
        if not commentsre and not spamre:

            # check for URL in body
            urlre = re.search(r'href=\\"(http://.+?)\\"', body)
            if urlre:
                url = urlre.group(1)

		# blogspot fake blog check
                urlre = re.search(r'http://(.+?)\.blogspot\.com', url)
                if urlre and len(urlre.group(1)) > 20:
                    #print ('blogspot detected:', url)
                    rejectlist.append(url)
                    continue

                body = re.sub('<.+?>.+?</.+?>', '', body)
                body = re.sub(' - $', '', body)

		# check for length
                if len(body) <= 15:
                    continue

		# check for 'new' body
                if not body in bodies:
                    bodies[body] = 1
                    internre = interntest.search(url)
                    if internre:
                        pass # TODO
                    else:

                        # Check spelling to see if the link text is in English
                        langtest = re.sub(r"\p{P}+", "", body)
                        wordcount = len(re.findall(r'\w+', langtest)) # redundant, see enchant.tokenize
                        errcount = 0
                        try :
                            spellcheck.set_text(langtest)
                            for err in spellcheck:
                                errcount += 1
                            try:
                                if ( (errcount/wordcount) > 0.5):
                                    flag = 1
                                else:
                                    rejectlist.append(url)
                            except ZeroDivisionError:
                                print ("empty title:", langtest)
                                #i += 1
                        except (UnicodeEncodeError, AttributeError):
                            flag = 1
		# body in bodies : frequent posts detection and storage ?
                else:
                    bodies[body] += 1

        if flag == 1:

            # Google News etc. URL filter # there might be a better way to perform the substitutions
            urlre = re.search(r'q=(http.+?)&amp', url)
            if urlre:
                url = urlre.group(1)
            urlre = re.search(r'url=(http.+?)&?', url)
            if urlre:
                url = urlre.group(1)

            if len(url) > 10:
                # store the link
                sublinks.append(url)
                # store the user behind the tweet
                if step == 1 or step == 3:
                    if subdict[marker] not in usersdone:
                        userstodo.append(subdict[marker])
                # log option
                if options.verbose is True:
                    print ('----------')
                    if step == 1 or step == 3:
                        print (subdict[marker])
                    try:
                        print (body)
                    except UnicodeEncodeError:
                        print ('body print problem')
                    print (url)

    # end of loop
    sublinks = list(set(sublinks))
    return sublinks


# fetch + analyze
def fetch_analyze(address, flswitch):
    global templinks
    jsoncode = req('http://friendfeed-api.com/v2/feed/' + address)
    if jsoncode is not 'error':
        templinks = findlinks(jsoncode, flswitch)
        links.extend(templinks)


# smart deep crawl
def smartdeep():
    global templinks
    hostnames = defaultdict(int)
    for link in templinks:
        hostname = urlparse(link).netloc
        hostnames[hostname] += 1
    try:
        ratio = len(templinks)/len(hostnames)
        if ratio >= 5: # could also be 7 or 10
            print (ratio)
            return 1
        else:
            return 0
    except ZeroDivisionError:
        return 0


# uniq lists
def uniqlists():
    global userstodo; userstodo = list(set(userstodo))
    global usersdone; usersdone = list(set(usersdone))
    global links; links = list(set(links))
    global rejectlist; rejectlist = list(set(rejectlist))
    # usersdone, userstodo, links, rejectlist = ([] for i in range(4)) ?


### LOOPS

# First pass : crawl of the homepage (public feed), skipped with the -u/--users switch

if options.users is False:
    fetch_analyze('public?maxcomments=0&maxlikes=0&num=100', 1)
    #jsoncode = (jsoncode.decode('utf-8')).encode('utf8')


# Second loop : go see the users on the list (and eventually their friends), skipped with the -s/--simple switch

if options.simple is False:

    uniqlists()

    for userid in userstodo:
        if options.requests is not None and total_requests >= options_requests:
            break
        fetch_analyze(str(userid) + '?maxcomments=0&maxlikes=0&num=100', 2)
        usersdone.append(userid)
        #if jsoncode is not 'error':
        #    templinks = findlinks(jsoncode, 2)
        #    links.extend(templinks)

	# smart deep crawl
        if options.deep is True:
           result = smartdeep()
           if result == 1:
               fetch_analyze(str(userid) + '?maxcomments=0&maxlikes=0&start=100&num=100', 2)

	# crawl the 'friends' page
        if options.friends is True:
            fetch_analyze(str(userid) + '/friends?maxcomments=0&maxlikes=0&num=100', 3)
            #jsoncode = req('http://friendfeed-api.com/v2/feed/' + userid + '/friends?maxcomments=0&maxlikes=0&num=100')
            #if jsoncode is not 'error':
                #templinks = findlinks(jsoncode, 3)
                #links.extend(templinks)

            # smart deep crawl
            if options.deep is True:
                result = smartdeep()
                if result == 1:
                    fetch_analyze(str(userid) + '/friends?maxcomments=0&maxlikes=100&num=100', 3)
                    #jsoncode = req('http://friendfeed-api.com/v2/feed/' + userid + '/friends?maxcomments=0&maxlikes=0&start=100&num=100')
                    #if jsoncode is not 'error':
                        #templinks = findlinks(jsoncode, 3)
                        #links.extend(templinks)


# Write all the logs
@atexit.register
def the_end():
    uniqlists()
    if options.verbose is True:
        print ('##########')
    print ('Requests:\t', total_requests)
    print ('Users (total):\t', len(usersdone))
    writefile('ff-usersdone', usersdone, 'w')
    print ('New users:\t', len(userstodo))
    writefile('ff-userstodo', userstodo, 'a')
    print ('Rejected:\t', len(rejectlist))
    writefile('ff-rejected', rejectlist, 'a')
    print ('Links:\t\t', len(links))
    writefile('ff-links', links, 'a')

    print ('Execution time (secs): {0:.2f}' . format(time.time() - start_time))