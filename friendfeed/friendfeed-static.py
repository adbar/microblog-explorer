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
import codecs

from enchant.checker import SpellChecker # see package 'python-enchant' on Debian/Ubuntu
spellcheck = SpellChecker("en_US")
langcheck = 0

from collections import defaultdict
bodies = defaultdict(int)

# no crawling limit indicated in the API documentation : http://friendfeed.com/api/documentation
sleeptime = 2.5

## FILTERS
# comments
reject = re.compile(r'"[0-9]+ comments?"')
# spam (small list, to be updated)
spam = re.compile(r'viagra|^fwd|gambling|casino|loans|cialis|price|shop', re.IGNORECASE) # also in urls ?
# internal links (no used)
interntest = re.compile(r'http://friendfeed.com/')

links = list()
rejectlist = list()

try:
    usersfile = open('users', 'r')
    users = usersfile.readlines()
    usersfile.close()
except IOError:
    users = list()



# time the whole script
start_time = time.time()



### SUBS

# write files (and not append)
def writefile(filename, listname):
    #filename = options.lcode + '_' + filename
    try:
        out = open(filename, 'w')
    except IOError:
        sys.exit ("could not open output file")
    for link in listname:
        out.write(link + "\n")
    out.close()

# Fetch URL
def req(url):
    req = Request(url)
    req.add_header('Accept-encoding', 'gzip')
    req.add_header('User-agent', 'Microblog-Explorer/0.2')

    try:
        response = urlopen(req)
    except (URLError, BadStatusLine) as e:
        print ("Error: %r" % e)
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
            if step is '1ststep':
                users.append(chunks[chunknum])
            #try:
            #    print (body)
            #except UnicodeEncodeError:
            #    print ("body print problem")

            urlre = re.search(r'q=(http.+?)&amp', url)
            if urlre:
                url = urlre.group(1)
            urlre = re.search(r'url=(http.+?)&?', url)
            if urlre:
                url = urlre.group(1)

            if len(url) > 10:
                links.append(url)
        #if not commentsre:
            #chunknum += 1
        chunknum += 1



jsoncode = req('http://friendfeed-api.com/v2/feed/public?maxcomments=0&maxlikes=0&num=100')
#jsoncode = (jsoncode.decode('utf-8')).encode('utf8')


findlinks(jsoncode, '1ststep');


users = list(set(users))
links = list(set(links))
rejectlist = list(set(rejectlist))



# Go see the users on the list

for userid in users:
    time.sleep(sleeptime)
    jsoncode = req('http://friendfeed-api.com/v2/feed/' + userid + '?maxcomments=0&maxlikes=0&num=100')
    if jsoncode is not 'error':
        findlinks(jsoncode, '2ndstep');
#http://friendfeed-api.com/v2/feed/ramelangidney?maxcomments=0&maxlikes=0&start=0&num=100 + start=100 etc.



users = list(set(users))
print ('Users:\t', len(users))
writefile('users', users)
links = list(set(links))
print ('Links:\t', len(links))
writefile('links', links)
rejectlist = list(set(rejectlist))
print ('Rejected:\t', len(rejectlist))
writefile('rejected', rejectlist)



print ('Execution time (secs): {0:.2f}' . format(time.time() - start_time))
