Microblog-Explorer
==================


The Microblog-Explorer project is about gathering links from social networks to use them as crawling seeds.

Other interests could be text analysis or network visualization, but they are not the priority right now.

The scripts are under heavy development, they work but are not optimized yet. They are tested on UNIX (Debian flavors), they should work on other UNIX-like systems provided the modules needed are installed.

The links that are obviously pointing at images or videos are filtered out.


Installation
------------

Recommandations for the Debian/Ubuntu systems (probably useful for other Linux distributions) :

* Install or make sure you have following packages installed : libtry-tiny-perl libstring-crc32-perl libhtml-strip-perl libhtml-clean-perl

* Open the CPAN console (e.g. sudo cpan) and say 'install Furl', as this Perl module is not installed by default, or let it by the LWP default. The script detects which module is available.



Identi.ca
---------

The files uploaded so far enable to gather external (and internal) links from identi.ca. The advantages compared to Twitter include the CC license of the messages, the absence of limitations (to my knowledge) and the relative small amount of messages (which can also be a problem).


### Hourly crawl

This Perl script is meant to gather recent links every hour, which currently translates to about 300 page views in about three minutes (4 threads, 0.5 sec sleep time between page views).

It scans the 15 first pages of the main timeline and retrieves the first page (i.e. the 20 most recent messages) of each user, tag and group it found.

It tries to spare requests by detecting users who have a low tweet frequency and storing them in lists of pages to skip (still experimental).

Usage : without arguments.

Writes a report on STDOUT and 5 files.


### Long-distance miner

The miner explores the user network starting from a 'USERS_TODO' list (which can be copied from the 'result-int' output of the other script). It guesses the total number of tweets by user and retrieves up to 400 of them (i.e. 20 pages per user). It performs the same operation with the following users and the followers.

Because of this exponential number of requests, it is wise to explore no more than a few hundred profiles at once. The script starts 4 threads and allows for a 3 seconds break between 2 requests on the same profile.

This script is still under development, it has not reached its optimal efficiency (neither on the client side, nor on identi.ca's).

Example (provided there are 100 new URLs in the `USERS_TODO` list) :

    perl long-distance-miner.pl 100

Writes a report on STDOUT and 5 files.


### Remarks

The API could be faster, but an account is needed (which is not the case for the Twitter API).

The Bash script deletes duplicates, it can be run before an export of the data or every day to reduce the size of the files :

    bash remove-duplicates.sh


Reddit
------

This crawler gathers (nearly) all external and internal links starting from a given reddit page, a multi-reddit expression or a given language code (which is a pre-compiled multi-reddit).

All the functions described here are featured by the API version which gets shorter pages (in JSON format) containing 100 links instead of 25. The official API limitations are respected, with a few more than 2 seconds between two requests.

There are 15 target languages available so far : Croatian, Czech, Danish, Finnish, French, German, Hindi, Italian, Norse, Polish, Portuguese, Romanian, Russian, Spanish and Swedish.

Using the spell-checker provided by the python-enchant package, the script discriminates between links whose titles are mostly English and others which are bound to be in the target language. Tests show that the probability to find URLs that lead to English text is indeed much higher concerning the 'suspicious' list. This option can be deactivated.

Usage examples :

	python reddit-crawl.py --starter http://www.reddit.com/r/Polska/
	python reddit-crawl.py -s Polska			# the same, shorter

	python reddit-crawl.py -l dkpol+denmark			# using a multi-reddit expression
	python reddit-crawl.py -l da				# the same, using a language code

	python reddit-crawl.py -l hi --no-language-check	# hindi, no links refused

Prints a report on STDOUT and creates files.

The 'weekly-crawl.sh' shell script performs a crawl of all the given languages.


FriendFeed
----------

Using the API, the script performs crawls according to the following options : 'simple' (homepage only), 'users' (only explore a given list of users), 'friends' (look for the friends channel), deep (a smart deep crawl targeting the interesting users, i.e. the users by which a significant number of relevant links was found).

As there are no official limitations, the time between two requests can vary. After a certain number of successful requests with little or no sleep, the server starts dropping most of the inbound connections.

The link selection is similar to the reddit crawls : using a spell-checked, the script discriminates between links whose titles are mostly English and others which are bound to be in the target language. This option can be bypassed manually by using `--no-language-check`.

The functionning is similar to the other scripts, except that here all the crawling ways through the social network are performed by the same script :

	python friendfeed-static.py -s	# or --simple : single retrieval of the public feed
	python friendfeed-static.py -u	# or --users : iterate through a list of users only
	-d or --deep option : perform a smart deep crawl (visit a user's history if it seems relevant)

For a complete list of the options (such as verbose or benchmark/random modes), please refer to the help section :

	python friendfeed-static.py -h

Prints a report on STDOUT and creates files.


Related Projects
--------------

For downstream applications :

* [FLUX-Toolchain](https://github.com/adbar/url-compressor) (filtering and language-identification, under development)

* [URL compressor](https://github.com/adbar/url-compressor)

Other crawling projects are hosted on [Google Code](http://code.google.com/u/114777084812550353886/)
