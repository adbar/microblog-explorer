#!/usr/bin/perl


###	This script is part of the microblog-explorer project (https://github.com/adbar/microblog-explorer).
###	It is brought to you by Adrien Barbaresi.
###	It is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used in combination with a language identification system (https://github.com/saffsd/langid.py) running as a server on port 9008. Please adjust the host parameter to your configuration (see below).


use strict;
use warnings;
use open ':encoding(utf8)';
use Encode qw(encode);
require Compress::Zlib;
use base 'HTTP::Message';
use Furl;
use LWP::UserAgent;
require LWP::Protocol::https;
use IO::Socket::SSL;
use Net::IDN::Encode ':all';
use URI::Split qw(uri_split uri_join);
use HTML::Strip;
use HTML::Clean;
use Time::HiRes qw( time );


die 'Usage: perl XX.pl [number of links to scan]' if (scalar (@ARGV) != 1);
my $links_count = $ARGV[0];

my @output :shared;
my (@urls, @done, %links_done, %hostnames, $finaluri, $clean_text, $confidence, $lang, $suspicious, @check_again);

my $todo = 'LINKS_TODO';
my $done = 'RESULTS_langid';

if (-e $done) {
	open (my $ldone, '<', $done);
	while (<$ldone>) {
		chomp;
		my @temp = split ("\t", $_);
		$hostnames{$temp[0]}++;
		my $join = $temp[0] . $temp[1];
		$links_done{$join}++;
	}
	close($ldone);
}

if (-e $todo) {
	open (my $ltodo, '<', $todo);
	while (<$ltodo>) {
		chomp($_);
		unless (exists $links_done{$_}) {
			push (@urls, $_);	
		}
	}
	close($ltodo);
}
else {
	die 'no todo list';
}

my %seen = ();
@urls = grep { ! $seen{ $_ }++ } @urls;
die 'not enough links in the list' if (scalar(@urls) < $links_count);
# my @temp = splice (@urls, 0, $links_count); # lots of RAM wasted for the remaining urls

my $start_time = time();

my @redirection = ('t.co', 'j.mp', 'is.gd', 'wp.me', 'bit.ly', 'goo.gl', 'xrl.us', 'ur1.ca', 'b1t.it', 'dlvr.it', 'ping.fm', 'post.ly', 'p.ost.im', 'on.fb.me', 'tinyurl.com', 'friendfeed.com');

my $furl = Furl::HTTP->new(
        agent   => 'Microblog-Explorer-0.1',
        timeout => 5,
	#headers => [ 'Accept-Encoding' => 'gzip' ],  # useless here
);

my ($req, $res);
my $ua = LWP::UserAgent->new;
my $can_accept = HTTP::Message::decodable;
$ua->agent("Microblog-Explorer-0.1");
$ua->timeout( 5 );



## Main loop
my $i = 0;
my $stack = 0;
open (my $out, '>>', $done);

foreach my $url (@urls) {
	$stack++;
	# check redirection
	$url =~ m/https?:\/\/(.+?)\//;
	my $short = $1;
	if ($short ~~ @redirection) {
		# found on http://stackoverflow.com/questions/2470053/how-can-i-get-the-ultimate-url-without-fetching-the-pages-using-perl-and-lwp
		$req = HTTP::Request->new(HEAD => $url);
		$req->header('Accept' => 'text/html');
		$res = $ua->request($req);
		if ($res->is_success) {
			$url = $res->request()->uri();
		}
		else {
			next;
		}
	}

	#check hostname
	my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
	next if ($auth !~ m/\./);
	next if ($scheme =~ m/^ftp/);
	my $finaluri = lc(uri_join($scheme, $auth));
	if (exists $hostnames{$finaluri}) {
		next;
	}
	else {
		$hostnames{$finaluri}++;
	}

	push (@done, $finaluri);

	# download, strip and put
	$req = HTTP::Request->new(GET => $finaluri);
	$req->header(
			'Accept' => 'text/html',
			'Accept-Encoding' => $can_accept,
		);
	# send request
  	$res = $ua->request($req);
	if ($res->is_success) {
		my $body = $res->decoded_content(charset => 'none');
		$i++;

		{ no warnings 'uninitialized';
			#my $body = $furl->get($finaluri);
			next if (length($body) < 100); # could be another value 
			my $h = new HTML::Clean(\$body);
			$h->strip();
			my $data = $h->data();

			my $hs = HTML::Strip->new();
			$clean_text = $hs->parse( $$data );
			$hs->eof;

			next if (length($clean_text) < 100); # could also be another value
			$clean_text = encode('UTF-8', $clean_text);
		}
		### WIDESTRING ERROR if no re-encoding, but re-encoding may break langid


	my ( $minor_version, $code, $msg, $headers, $res ) = $furl->request(
		method  => 'PUT',
		host    => '*.*.*.*', # please fill this out
		port    => 9008,
		path_query => 'detect',
		content	=> $clean_text,
	);
	if ($code == 200) {
			$suspicious = 0;
			$res =~ m/"confidence": (.+?), "language": "([a-z]+?)"/;
			$confidence = $1;
			$lang = $2;

			# problems with encoding changes, these codes can also be bg, ja, ru, etc.
			if ( ($lang eq "zh") || ($lang eq "qu") || ($lang eq "ps") || ($lang eq "la") ) { 
				$suspicious = 1;
			}
			elsif ( ($lang eq "el") && ($auth !~ m/\.gr$/) && ($confidence != 1) ) {
				$suspicious = 1;
			}
			elsif ( ($lang eq "lb") && ($auth !~ m/\.lu$/) ) {
				$suspicious = 1;
			}

			if ($suspicious == 1) {
				my $checkurl = lc($finaluri) . "\t" . $path . "\t" . $lang . "\t" . $confidence;
				push (@check_again, $checkurl);
			}
			else {
			my $output = lc($finaluri) . "\t" . lc($path) . "\t" . $lang . "\t" . $confidence;
			print $out $output . "\n";
			}
		}
	}
	if ($i == $links_count) {
		last;
	}
}

close($out);

splice(@urls, 0, $stack);
open (my $ltodo, '>', 'LINKS_TODO');
print $ltodo join("\n", @urls);
close($ltodo);

open (my $check_again, '>>', 'LINKS_TO-CHECK');
print $check_again join("\n", @check_again);
close($check_again);

print "urls: " . $links_count . "\n";
print "visited: " . $i . "\n";
print "suspicious: " . scalar(@check_again) . "\n";
my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);
