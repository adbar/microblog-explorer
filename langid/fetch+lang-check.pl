#!/usr/bin/perl


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used in combination with a language identification system (https://github.com/saffsd/langid.py) running as a server on port 9008 : python langid.py -s
# Please adjust the host parameter to your configuration (see below).


use strict;
use warnings;
use Getopt::Long;
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



my ($help, $hostreduce, $wholelist, $fileprefix, $links_count);

usage() if ( @ARGV < 1
	or ! GetOptions ('h|help' => \$help, 'fileprefix|fp=s' => \$fileprefix, 'hostreduce|hr' => \$hostreduce, 'all|a' => \$wholelist, 'links|l=i' => \$links_count)
	or defined $help
	or (defined $wholelist && defined $links_count) );

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl XX.pl [--help|-h] [--fileprefix|-fp] prefix [--all|-a] [--links|-l] number [--hostreduce|-hr] \n\n";
	print "prefix : used to identify the files\n";
	print "EITHER --all OR a given number of links\n";
	print "hostreduce : keep only the hostname in each url\n\n";
	exit;
}


my (@urls, @done, %links_done, %hostnames, $finaluri, $clean_text, $confidence, $lang, $suspicious, @check_again, @output, $join);

my $todo = 'LINKS-TODO';
my $done = 'RESULTS-langid';
my $tocheck = 'LINKS-TO-CHECK';

if (defined $fileprefix) {
	$todo = $fileprefix . "_" . $todo;
	$done = $fileprefix . "_" . $done;
	$tocheck = $fileprefix . "_" . $tocheck;
}

if (-e $done) {
	open (my $ldone, '<', $done);
	while (<$ldone>) {
		chomp;
		my @temp = split ("\t", $_);
		if (scalar (@temp) == 3) {
			$hostnames{$temp[0]}++;
			$join = $temp[0];
		}
		elsif (scalar (@temp) == 4) {
			$hostnames{$temp[0]}++;
			$join = $temp[0] . $temp[1];
		}
		$links_done{$join}++;
	}
	close($ldone);
}

if (-e $todo) {
	open (my $ltodo, '<', $todo);
	while (<$ltodo>) {
		chomp($_);
		# Filters
		unless (exists $links_done{$_}) {
			unless ( ($_ =~ m/\.ogg$|\.mp3$|\.avi$|\.mp4$/) || ($_ =~ m/\.jpg$|\.JPG$|\.jpeg$|\.png$|\.gif$/) ) {
				push (@urls, $_);
			}
		}
	}
	close($ltodo);
}
else {
	die 'No todo list found under this file name: ' . $todo;
}

my %seen = ();
@urls = grep { ! $seen{ $_ }++ } @urls;
die 'not enough links in the list' if ((defined $links_count) && (scalar(@urls) < $links_count));
# my @temp = splice (@urls, 0, $links_count); # lots of RAM wasted for the remaining urls

my $start_time = time();

my @redirection = ('t.co', 'j.mp', 'is.gd', 'wp.me', 'bit.ly', 'goo.gl', 'xrl.us', 'ur1.ca', 'b1t.it', 'dlvr.it', 'ping.fm', 'post.ly', 'p.ost.im', 'on.fb.me', 'tinyurl.com', 'friendfeed.com');

my $furl = Furl::HTTP->new(
        agent   => 'Microblog-Explorer/0.1',
        timeout => 5,
	#headers => [ 'Accept-Encoding' => 'gzip' ],  # useless here
);

my ($req, $res);
my $ua = LWP::UserAgent->new;
my $can_accept = HTTP::Message::decodable;
$ua->agent("Microblog-Explorer/0.1");
$ua->timeout( 5 );


## Main loop
my $i = 0;
my $stack = 0;
open (my $out, '>>', $done);
open (my $check_again, '>>', $tocheck);

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

	if (defined $hostreduce) {
		$finaluri = lc(uri_join($scheme, $auth));
	}
	else {
		$finaluri = lc(uri_join($scheme, $auth, $path));
	}

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
			next if (length($body) < 100); # could be another value 
			my $h = new HTML::Clean(\$body);
			$h->strip();
			my $data = $h->data();

			my $hs = HTML::Strip->new();
			$clean_text = $hs->parse( $$data );
			$hs->eof;

			next if (length($clean_text) < 100); # could also be another value
		}

		# Furl alternative
		my ( $minor_version, $code, $msg, $headers, $res );
		eval { # WIDESTRING ERROR if no re-encoding, but re-encoding may break langid
			( $minor_version, $code, $msg, $headers, $res ) = $furl->request(
				method  => 'PUT',
				host    => '78.46.186.58',
				port    => 9008,
				path_query => 'detect',
				content	=> $clean_text,
			);
		};
		if ($@) {
			print "An error occurred ($@), continuing\n";
			$clean_text = encode('UTF-8', $clean_text);
			eval {
				( $minor_version, $code, $msg, $headers, $res ) = $furl->request(
					method  => 'PUT',
					host    => '78.46.186.58',
					port    => 9008,
					path_query => 'detect',
					content	=> $clean_text,
				);
			};
			if ($@) {
				print "ERROR: $@" . "url: " . $finaluri;
				next;
			}
		}
		if ($code == 200) {
			$suspicious = 0;
			$res =~ m/"confidence": (.+?), "language": "([a-z]+?)"/;
			$confidence = $1;
			$lang = $2;

			# problems with encoding changes, these codes can also be bg, ja, ru, etc.
			if ($confidence < 0.5) {
				$suspicious = 1;
			}
			elsif ( ($lang eq "zh") || ($lang eq "qu") || ($lang eq "ps") || ($lang eq "la") || ($lang eq "lo") || ($lang eq "an") ) { 
				$suspicious = 1;
			}
			elsif ( ($lang eq "el") && ($auth !~ m/\.gr$/) && ($confidence != 1) ) {
				$suspicious = 1;
			}
			elsif ( ($lang eq "lb") && ($auth !~ m/\.lu$/) ) {
				$suspicious = 1;
			}

			my ($checkurl, $output);
			if ($suspicious == 1) {
				if (defined $hostreduce) {
					$checkurl = lc($finaluri) . "\t" . lc($path) . "\t" . $lang . "\t" . $confidence;
				}
				else {
					$checkurl = lc($finaluri) . "\t" . $lang . "\t" . $confidence;
				}
				print $check_again $checkurl . "\n";
			}
			else {
				if (defined $hostreduce) {
					$output = lc($finaluri) . "\t" . lc($path) . "\t" . $lang . "\t" . $confidence;
				}
				else {
					$output = lc($finaluri) . "\t" . $lang . "\t" . $confidence;
				}
				print $out $output . "\n";
			}
		}
		elsif ($code == 500) {
			print "no langid server available\n";
			exit;
		}
	}
	if (defined $links_count) {
		if ($i == $links_count) {
			last;
		}
	}
}

close($out);
close($check_again);

splice(@urls, 0, $stack);
open (my $ltodo, '>', $todo);
print $ltodo join("\n", @urls);
close($ltodo);

print "urls: " . $stack . "\n";
print "visited: " . $i . "\n";
print "suspicious: " . scalar(@check_again) . "\n";
my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);