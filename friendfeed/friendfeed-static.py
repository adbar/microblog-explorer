#!/usr/bin/python


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

### The official API module for Python is much more complete : https://code.google.com/p/friendfeed-api/


#####			SCRIPT OUTLINE			#####
###
###	1. Initialize					
###		import functions
###		parse arguments
###		open files
###		time limits and filters
###	2. Functions
###		write/append to files
###		fetch URL
###		find interesting external links
###		fetch + analyze
###		smart deep crawl
###		uniq lists
###	3. Main loop
###		crawl of the homepage
###		users on the list
###	at exit : write all the logs
###
			####################



# Import functions
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
from urlparse import urlparse
import atexit
import os
import random

from enchant.checker import SpellChecker # see package 'python-enchant' on Debian/Ubuntu
spellcheck = SpellChecker("en_US")
langcheck = 0

from collections import defaultdict
bodies = defaultdict(int)


# TODO:
# interesting tld-extractor : https://github.com/john-kurkowski/tldextract
# todo/done ?
# internal links
# -df bug ?
# reziubqzecdpoin... filter
# frequent posts detection ?


## Parse arguments and options
parser = optparse.OptionParser(usage='usage: %prog [options] arguments')
parser.add_option("-s", "--simple", dest="simple", action="store_true", default=False, help="simple crawl ONLY (just the public feed)")
parser.add_option("-u", "--users", dest="users", action="store_true", default=False, help="users crawl ONLY (without public feed)")
parser.add_option("-f", "--friends", dest="friends", action="store_true", default=False, help="friends crawl")
parser.add_option("-d", "--deep", dest="deep", action="store_true", default=False, help="smart deep crawl")
parser.add_option("-b", "--benchmark", dest="benchmark", action="store_true", default=False, help="benchmarking mode")
parser.add_option("--no-language-check", dest="nolangcheck", action="store_true", default=False, help="disable the language check")
parser.add_option("-r", "--requests", dest="requests", help="max requests")
parser.add_option("-v", "--verbose", dest="verbose", action="store_true", default=False, help="debug mode (body and ids info)")
options, args = parser.parse_args()


userstodo, usersdone, links, rejectlist, templinks, nodistinction, benchmarklist = ([] for i in range(7))


# Check for already existing files / open file
try:
    usersfile = open('ff-userstodo', 'r')
    for line in usersfile:
        userstodo.append(line.rstrip())
    userstodo = list(set(userstodo))
    usersfile.close()
except IOError:
    if options.users is True:
        print ('"ff-userstodo" file mandatory with the -u/--users switch')
        os._exit(1)
    else:
        pass

try:
    usersfile = open('ff-usersdone', 'r')
    for line in usersfile:
        usersdone.append(line.rstrip())
    usersdone = list(set(usersdone))
    usersfile.close()
except IOError:
    pass



## INITIALIZE

# time the whole script
start_time = time.time()

# nothing indicated in the API documentation : http://friendfeed.com/api/documentation
# 2 secs seem to be close to the limit though
sleeptime = 2
timelimit = 10
total_requests = 0
total_errors = 0


## FILTERS

# comments
reject = re.compile(r'"[0-9]+ comments?"')
# spam (small list, to be updated)
# http://www.twithawk.com/faq/stopwords
spam = re.compile(r'viagra|^fwd|gambling|casino|loans|cialis|price|shop|buyonlinetab|buytabonline|streaming|store|download', re.IGNORECASE) # also in urls ?
# internal links (no used)
interntest = re.compile(r'http://friendfeed.com/')


######################		FUNCTIONS


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
    #except (URLError) as e:
    except Exception as e:
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
    global userstodo
    global usersdone
    global nodistinction
    global benchmarklist

    ## 'If I strip everything I don't want, I'll be able to fetch what I want'...
    ## This is ugly : to be replaced by a 'real' parser ?
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
        if not reject.search(body) and not spam.search(body):

            # check for URL in body
            urlre = re.search(r'href=\\"(http://.+?)\\"', body)
            if urlre:
                url = urlre.group(1)
                if options.benchmark is True:
                    nodistinction.append(url)

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
                    if interntest.search(url):
                        pass # TODO
                    else:
                        if options.nolangcheck is False and options.benchmark is False:
                            # Check spelling to see if the link text is in English
                            langtest = re.sub(r'\p{P}+', '', body)
                            wordcount = len(re.findall(r'\w+', langtest)) # redundant, see enchant.tokenize
                            errcount = 0
                            try:
                                spellcheck.set_text(langtest)
                                for err in spellcheck:
                                    errcount += 1
                                try:
                                    if ( (errcount/wordcount) > 0.5):
                                        flag = 1
                                        if options.benchmark is True and step == 1:
                                            benchmarklist.append(1)
                                    else:
                                        rejectlist.append(url)
                                        if options.benchmark is True and step == 1:
                                            benchmarklist.append(0)
                                # the length of body has been checked, so that means it contained only punctuation marks
                                except ZeroDivisionError:
                                    flag = 1
                            # if the string couldn't be translated properly, it is also interesting
                            except (UnicodeEncodeError, AttributeError):
                                flag = 1
                        else:
                            if options.benchmark is True:
                                # values supposed to be realistic
                                if step == 1:
                                    uberlimit = 0.08
                                elif step == 2:
                                    uberlimit = 0.5
                                if random.random() < uberlimit:
                                    flag = 1
                                    benchmarklist.append(1)
                                else:
                                    benchmarklist.append(0)
                            else:
                                flag = 1
		# body in bodies : frequent posts detection and storage ?
                else:
                    bodies[body] += 1

        # if the link seems promising...
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
    global total_errors
    jsoncode = req('http://friendfeed-api.com/v2/feed/' + address)
    if jsoncode is not 'error':
        templinks = findlinks(jsoncode, flswitch)
        links.extend(templinks)
    else:
        total_errors += 1
        return 'error'
    return 1


# smart deep crawl
def smartdeep():
    global templinks
    hostnames = list()
    for link in templinks:
        hostname = urlparse(link).netloc
        hostnames.append(hostname)
    hostnames = list(set(hostnames))
    #writefile('ff-templinks', templinks, 'a')
    #writefile('ff-hostnames', hostnames, 'a')
    try:
        ratio = len(hostnames)/len(templinks)
        if ratio >= 0.2:	# could also be 0.05 or 0.075
            if options.verbose is True:
                print (ratio)
            return 1
        else:
            return 0
    except ZeroDivisionError:
        return 0


# uniq lists
def uniqlists():
    global userstodo; userstodo = list(set(userstodo));	#userstodo = filter(None, userstodo)
    global usersdone; usersdone = list(set(usersdone))
    global links; links = list(set(links))
    global rejectlist; rejectlist = list(set(rejectlist))
    global nodistinction; nodistinction = list(set(nodistinction))


######################		END OF FUNCTIONS


### LOOPS

# First pass : crawl of the homepage (public feed), skipped with the -u/--users switch

if options.users is False:
    value = fetch_analyze('public?maxcomments=0&maxlikes=0&num=100', 1)
    if value is 'error' and total_errors == 1:
        #sleeptime *= 2
        for n in range(1, 3):
            time.sleep(sleeptime)
            value = fetch_analyze('public?maxcomments=0&maxlikes=0&num=100', 1)
            if value is not 'error':
                break
        
    #jsoncode = (jsoncode.decode('utf-8')).encode('utf8')


# Second loop : go see the users on the list (and eventually their friends), skipped with the -s/--simple switch

if options.simple is False:

    uniqlists()

    for userid in userstodo:
        if options.requests is not None and total_requests >= options.requests:
            break
        usersdone.append(userid)
        value = fetch_analyze(str(userid) + '?maxcomments=0&maxlikes=0&num=100', 2)

	# smart deep crawl
        if options.deep is True and value is not 'error':
           for num in range(1, 6):
               result = smartdeep()
               if result == 1:
                   value = fetch_analyze(str(userid) + '?maxcomments=0&maxlikes=0&start=' + str(num) + '00&num=100', 2)
                   if value is 'error':
                       break

    # crawl the 'friends' page
    if options.friends is True:
        for userid in userstodo:
            value = fetch_analyze(str(userid) + '/friends?maxcomments=0&maxlikes=0&num=100', 3)

            # smart deep crawl
            if options.deep is True and value is not 'error':
               for num in range(1, 6):
                   result = smartdeep()
                   if result == 1:
                       value = fetch_analyze(str(userid) + '/friends?maxcomments=0&maxlikes=0&start=' + str(num) + '00&num=100', 3)
                       if value is 'error':
                           break


# Exit strategy
# Write all the logs
@atexit.register
def the_end():
    uniqlists()
    for user in usersdone:
        try:
            userstodo.remove(user)
        except ValueError:
            pass

    # print infos
    if options.verbose is True:
        print ('##########')
    print ('Requests:\t', total_requests)
    print ('Errors:\t\t', total_errors)
    print ('Users (total):\t', len(usersdone))

    # append/write to files
    writefile('ff-usersdone', usersdone, 'a')
    print ('New users:\t', len(userstodo))
    writefile('ff-userstodo', userstodo, 'w')
    print ('Rejected:\t', len(rejectlist))
    writefile('ff-rejected', rejectlist, 'a')
    print ('Links:\t\t', len(links))
    writefile('ff-links', links, 'a')

    # benchmark option
    if options.benchmark is True:
        try:
            print ('Benchmark: {0:.2f}' . format(sum(benchmarklist)/len(benchmarklist)))
        except ZeroDivisionError:
            print ('Benchmark: ', '0')
        writefile('ff-benchmarklist', benchmarklist, 'a')
        writefile('ff-nodistinction', nodistinction, 'a')

    # execution time and exit
    print ('Execution time (secs): {0:.2f}' . format(time.time() - start_time))
