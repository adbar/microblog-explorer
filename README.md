Microblog-Explorer
==================


The Microblog-Explorer project is about gathering links from social networks to use them as crawling seeds.

Other interests could be text analysis or network visualization, but they are not the priority right now.

The scripts are under heavy development, they work but are not optimized yet. They are tested on UNIX (Debian flavors), they should work on other UNIX-like systems provided the modules needed are installed.

The links that are obviously pointing at images or videos are filtered out.


Installation
------------

Recommandations for the Debian/Ubuntu systems (probably useful for other Linux distributions) :

Install or make sure you have following packages installed : libtry-tiny-perl libstring-crc32-perl libhtml-strip-perl libhtml-clean-perl

Open the CPAN console (e.g. sudo cpan) and say 'install Furl', as this Perl module is not installed by default.



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

All the functions described here are featured by the API version which gets shorter pages (in JSON format) with 100 links instead of 25. It is thus much faster and it is recommended, the older HTML-based one remains in case the API rules change.

Target languages available so far : Czech, Danish, German, Spanish, Finnish, French, Italian, Norse, Polish, Portuguese and Romanian.

Using the spell-checker provided by the python-enchant package, the script discriminates between links whose titles are mostly English and others which are bound to be in the target language. Tests show that the probability to find urls that lead to English text is indeed much higher concerning the 'suspicious' list.

Usage examples :

	python reddit-crawl.py --starter http://www.reddit.com/r/Polska/
	python reddit-crawl.py -s Polska		# the same, shorter

	python reddit-crawl.py -l dkpol+denmark		# using a multi-reddit expression
	python reddit-crawl.py -l da			# the same, using a language code

Prints a report on STDOUT and creates X files.


Language identification
-----------------------

There are two scripts in the directory named 'langid' which are to be used with the [langid.py language identification system](https://github.com/saffsd/langid.py).


### [langid.py](https://github.com/saffsd/langid.py) server

The langid.py server can be started as follows :

    python langid.py -s
    python langid.py -s --host=localhost &> langid-log &	# as a background process on localhost


### Check a list of URLs for redirections

Send a HTTP HEAD request to see where the link is going.

    perl resolve-redirects.pl --timeout 10 --all FILE
    perl resolve-redirects.pl -h			# display all the options

Prints a report on STDOUT and creates X files.


### Clean the list of URLs

Removes non-http protocols, images, PDFs, audio and video files, ad banners, feeds :

    python clean_urls.py -i INPUTFILE -o OUTPUTFILE
    python clean_urls.py -h				# for help


### Fetch the pages, clean them and send them as a PUT request to the server

This Perl script fetches the webpages of a list, strips the HTML code, sends raw text to a server instance of langid.py and retrieves the answer.
Usage : takes a number of links to analyze as argument. Example (provided there is a list named `LINKS_TODO`) :

    perl fetch+lang-check.pl 200
    perl fetch+lang-check.pl -h		# display all the options

Prints a report on STDOUT and creates X files.

Sampling approach (option --hostreduce) : to be explained.


### Multi-threading

Parallel threads are implemented, the bash script starts several instances of the scripts, merges and saves the results.

Following syntax : filename + number of links to check + number of threads

Resolve redirections :

     bash res-red-threads.sh FILE 100000 10 &> rr.log &

Fetch and send the pages to lang-id :
Expects the langid-server to run on port 9008.
Expects the clean_urls.py pythons script (in order to avoid crawler traps).
 + results already collected (not required)

    (bash threads.sh FILE 100000 8 &> fs.log &)		# as a detached background process


### Get statistics and interesting links

The list written by the Perl script can be examined using a Python script which features a summary of the languages concerned (language code, number of links and percentage). It also to gather a selection of links by choosing relevant language codes.

Usage: lang-stats+selection.py [options]

Getting the statistics of a list named `RESULTS_langid` :

    python lang-stats+selection.py --input-file=RESULTS_langid

Getting the statistics as well as a prompt of the languages to select and store them in a file :

    python lang-stats+selection.py -l --input-file=... --output-file=...


Related Projects
--------------

For a downstream application see the [URL compressor](https://github.com/adbar/url-compressor) (also under development)

Other crawling projects are hosted on [Google Code](http://code.google.com/u/114777084812550353886/)
