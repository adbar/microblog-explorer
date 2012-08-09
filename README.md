The microblog-explorer project is about gathering links from social networks to use them as crawling seeds.

Other interests could be text analysis or network visualization, but they are not the priority right now.

The files uploaded so far enable to gather external (and internal) links from identi.ca. The advantages compared to Twitter include the CC license of the messages, the absence of limitations (to my knowledge) and the relative small amount of messages (which can also be a problem).

The scripts are under heavy development, they work but are not optimized yet. They are tested on UNIX (Debian flavours), they should work on other UNIX-like systems provided the modules needed are installed.

The Perl script is meant to gather recent links every hour, which currently translates to about 300 page views in less than three minutes.

The Bash script deletes duplicates, it can be run before an export of the data or every day to reduce the size of the files.

For a downstream application see my URL compressor : adbar/url-compressor (also under development)
