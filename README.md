Microblog-Explorer
==================


The microblog-explorer project is about gathering links from social networks to use them as crawling seeds.

Other interests could be text analysis or network visualization, but they are not the priority right now.

The files uploaded so far enable to gather external (and internal) links from identi.ca. The advantages compared to Twitter include the CC license of the messages, the absence of limitations (to my knowledge) and the relative small amount of messages (which can also be a problem).

The scripts are under heavy development, they work but are not optimized yet. They are tested on UNIX (Debian flavours), they should work on other UNIX-like systems provided the modules needed are installed.


Hourly crawl
------------

This Perl script is meant to gather recent links every hour, which currently translates to about 300 page views in about three minutes (4 threads, no sleep time between page views).

It scans the 15 first pages of the main timeline and retrieves the first page (i.e. the 20 most recent messages) of each user, tag and group it found.

It tries to spare requests by detecting users who have a low tweet frequency and storing them in lists of pages to skip (still experimental).

Usage : without arguments.
Writes a report on STDOUT and 5 files.


Long-distance miner
-------------------

The miner explores the user network starting from a 'USERS_TODO' list (which can be copied from the 'result-int' output of the other script). It guesses the total number of tweets by user and retrieves up to 400 of them (i.e. 20 pages per user). It performs the same operation with the following users and the followers.

Because of this exponential number of requests, it is wise to explore no more than a few hundred profiles at once. The script starts 4 threads and allows for a two seconds break between two requests on the same profile.

This script is still under development, it has not reached its optimal efficiency (neither on the client side, nor on identi.ca's). The error rate is around 10%, although the urls seem to be valid.

Example : perl long-distance-miner.pl 100 (provided there are 100 new URLs in the todo-list).
Writes a report on STDOUT and 5 files.


Remarks
-------

The API could be faster, but an account is needed (which is not the case for the Twitter API).

The Bash script deletes duplicates, it can be run before an export of the data or every day to reduce the size of the files.


Related Projects
--------------

For a downstream application see the [URL compressor](https://github.com/adbar/url-compressor) (also under development)

Other crawling projects are hosted on [Google Code](http://code.google.com/u/114777084812550353886/)
