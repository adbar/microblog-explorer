#!/usr/bin/perl


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used in combination with a language identification system (https://github.com/saffsd/langid.py) running as a server on port 9008 : python langid.py -s
# Please adjust the host parameter to your configuration (see below).


use strict;
use warnings;
use Getopt::Long;
use Fcntl qw(:flock SEEK_END);
use Encode qw(encode);
require Compress::Zlib;
use base 'HTTP::Message';
use Furl;
use LWP::UserAgent;
require LWP::Protocol::https;
#require LWPx::ParanoidAgent; # on Debian/Ubuntu package liblwpx-paranoidagent-perl
#use IO::Socket::SSL;
#use Net::IDN::Encode ':all';
use URI::Split qw(uri_split uri_join);
use HTML::Strip;
use HTML::Clean;
use Time::HiRes qw( time sleep );
use Try::Tiny; # on Debian/Ubuntu package libtry-tiny-perl


my ($help, $seen, $hostreduce, $wholelist, $fileprefix, $filesuffix, $links_count);

usage() if ( @ARGV < 1
	or ! GetOptions ('help|h' => \$help, 'seen|s=s' => \$seen, 'fileprefix|fp=s' => \$fileprefix, 'filesuffix|fs=s' => \$filesuffix, 'hostreduce|hr' => \$hostreduce, 'all|a' => \$wholelist, 'links|l=i' => \$links_count)
	or defined $help
	or (defined $wholelist && defined $links_count) );

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl XX.pl [--help|-h] [--seen|-s] [--fileprefix|-fp] prefix [--filesuffix|-fs] suffix [--all|-a] [--links|-l] number [--hostreduce|-hr] \n\n";
	print "seen : file containing the urls to skip\n";
	print "prefix : used to identify the files\n";
	print "EITHER --all OR a given number of links\n";
	print "hostreduce : keep only the hostname in each url\n\n";
	exit;
}


my (@urls, %links_done, %hostnames, $finaluri, $clean_text, $confidence, $lang, $suspicious, @output, $join);

my $todo = 'LINKS-TODO';
my $done = 'RESULTS-langid'; # may change
my $tocheck = 'LINKS-TO-CHECK';

my $errfile = 'ERRORS';
open (my $errout, ">>", $errfile) or die "Cannot open ERRORS file : $!\n";

# http://perldoc.perl.org/functions/flock.html
sub lock {
	my ($fh) = @_;
	flock($fh, LOCK_EX) or die "Cannot lock ERRORS file - $!\n";
	# and, in case someone appended while we were waiting...
	seek($fh, 0, SEEK_END) or die "Cannot seek ERRORS file - $!\n";
}
sub unlock {
	my ($fh) = @_;
	flock($fh, LOCK_UN) or die "Cannot unlock ERRORS file - $!\n";
}

if (defined $fileprefix) {
	$todo = $fileprefix . "_" . $todo;
	$done = $fileprefix . "_" . $done; # may change
	$tocheck = $fileprefix . "_" . $tocheck;
}

if (defined $filesuffix) {
	$todo = $todo . "." . $filesuffix;
	$done = $done . "." . $filesuffix; # may change
	$tocheck = $tocheck . "." . $filesuffix;
}

if ((defined $seen) && (-e $seen)) {
	open (my $ldone, '<', $seen);
	while (<$ldone>) {
		chomp;
		$_ =~ s/^http:\/\///; # spare memory space
		if ($_ =~ m/\t/) {
			my @temp = split ("\t", $_);
			# two possibilities according to the 'host-reduce' option
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
		else { # if it's just a 'simple' list of urls
			$links_done{$_}++;
		}
	}
	close($ldone);
}

if (-e $todo) {
	open (my $ltodo, '<', $todo);
	while (<$ltodo>) {
		chomp;
		$_ =~ s/^http:\/\///; # spare memory space
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
        timeout => 10,
	#headers => [ 'Accept-Encoding' => 'gzip' ],  # useless here
);

my ($req, $res);
my $ua = LWP::UserAgent->new; # another possibility : my $ua = LWPx::ParanoidAgent->new;
my $can_accept = HTTP::Message::decodable;
$ua->agent("Microblog-Explorer/0.1");
$ua->timeout(10);


## Main loop
my $i = 0;
my $stack = 0;
my $suspcount = 0;
open (my $out, '>>', $done);
open (my $check_again, '>>', $tocheck);

foreach my $url (@urls) {
	$stack++;
	unless ($url =~ m/^http/) {
		$url = "http://" . $url; # consequence of sparing memory space
	}

	# time process
	## http://stackoverflow.com/questions/1165316/how-can-i-limit-the-time-spent-in-a-specific-section-of-a-perl-script
	## http://stackoverflow.com/questions/3427401/perl-make-script-timeout-after-x-number-of-seconds
	{ no warnings 'exiting';
	#eval {
	try {
	local $SIG{ALRM} = sub { die "TIMEOUT\n" };
	alarm 30;

	# check redirection
	$url =~ m/https?:\/\/(.+?)\//;
	my $short = $1;
	if ( ($short ~~ @redirection) || (($url =~ m/\.[a-z]+\//) && (length($url) < 30)) ) { # not fully efficient
		# found on http://stackoverflow.com/questions/2470053/how-can-i-get-the-ultimate-url-without-fetching-the-pages-using-perl-and-lwp
		$req = HTTP::Request->new(HEAD => $url);
		$req->header('Accept' => 'text/html');
		$res = $ua->request($req);
		if ($res->is_success) {
			$url = $res->request()->uri();
		}
		else {
			lock($errout);
			print $errout "Dropped (redirection):\t" . $url . "\n";
			unlock($errout);
			$url =~ s/^http:\/\///;
			$finaluri = lc($url);
			$hostnames{$finaluri}++;
			alarm 0;
			next;
		}
	}

	#check hostname
	my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
	if (($auth !~ m/\./) || ($scheme =~ m/^ftp/)) {
		alarm 0;
		next;
	}

	if (defined $hostreduce) {
		$finaluri = lc(uri_join($scheme, $auth));
	}
	else {
		$finaluri = lc(uri_join($scheme, $auth, $path));
	}
		
	my $temp_short = $finaluri;
	$temp_short =~ s/^http:\/\///;
	$temp_short = lc($temp_short);
	if ( (exists $hostnames{$temp_short}) || ($links_done{$temp_short}) ) {
		alarm 0;
		next;
	}
	else {
		$hostnames{$temp_short}++;
	}

	# download, strip and put
	$req = HTTP::Request->new(GET => $finaluri);
	$req->header(
			'Accept' => 'text/html',
			'Accept-Encoding' => $can_accept,
		);
	# send request
  	$res = $ua->request($req);
	if ($res->is_success) {
		# check the size of the page (to avoid a memory overflow)
		my $testheaders = $res->headers;
		if ($testheaders->content_length) {
			if ($testheaders->content_length > 500000) {
				lock($errout);
				print $errout "Dropped (by content-size):\t" . $finaluri . "\n";
				unlock($errout);
				alarm 0;
				next;
			}
		}
		my $body = $res->decoded_content(charset => 'none');
		$i++;

		{ no warnings 'uninitialized';
			if (length($body) < 100) { # could be another value
				lock($errout);
				print $errout "Dropped (by body size):\t" . $finaluri . "\n";
				unlock($errout);
				alarm 0;
				next;
			}
			my $h = new HTML::Clean(\$body);
			$h->strip();
			my $data = $h->data();

			my $hs = HTML::Strip->new();
			$clean_text = $hs->parse( $$data );
			$hs->eof;

			if (length($clean_text) < 100) { # could also be another value
				lock($errout);
				print $errout "Dropped (by clean size):\t" . $finaluri . "\n";
				unlock($errout);
				alarm 0;
				next;
			}
		}
		my $tries = 0;
		FURLCHECK: # label to redo this part
		# Furl alternative
		my ( $minor_version, $code, $msg, $headers, $res );
		# WIDESTRING ERROR if no re-encoding, but re-encoding may break langid
		try {
			( $minor_version, $code, $msg, $headers, $res ) = $furl->request(
				method  => 'PUT',
				host    => '78.46.186.58',
				port    => 9008,
				path_query => 'detect',
				content	=> $clean_text,
			);
		}
		catch {
			#print "An error occurred ($@), continuing\n";
			$clean_text = encode('UTF-8', $clean_text);
			try {
				( $minor_version, $code, $msg, $headers, $res ) = $furl->request(
					method  => 'PUT',
					host    => '78.46.186.58',
					port    => 9008,
					path_query => 'detect',
					content	=> $clean_text,
				);
			}
			catch {
				lock($errout);
				print $errout "ERROR: $@" . "\turl:\t" . $finaluri;
				unlock($errout);
				alarm 0;
				next;
			};
		};
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
				$suspcount++;
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
			# Make sure the langid server is really down (may still be an issue with multi-threading)
			$tries++;
			if ($tries <= 5) {
				sleep(0.25);
				goto FURLCHECK;
			}
			else {
				print "no langid server available\n";
				last;
			}
		}
	}
	else {
		lock($errout);
		print $errout "Dropped (not found):\t" . $finaluri . "\n";
		unlock($errout);
	}

	alarm 0;
	} # end of try (timeout)
	catch {
		if ($_ eq "TIMEOUT\n") {
			lock($errout);
			print $errout "Handling timeout problem:\t" . $finaluri . "\n";
			unlock($errout);
		}
		else {
			die $_;
		}
	};
	} # end of 'no warnings exiting'
	# end the loop if the given number of urls was reached
	if (defined $links_count) {
		last if ($i == $links_count);
	}
}

close($out);
close($check_again);
close($errout);

splice(@urls, 0, $stack);
open (my $ltodo, '>', $todo);
print $ltodo join("\n", @urls);
close($ltodo);

print "urls: " . $stack . "\n";
print "visited: " . $i . "\n";
print "suspicious: " . $suspcount . "\n";
my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);