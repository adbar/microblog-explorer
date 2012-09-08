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
use IO::Socket::SSL;
#use Net::IDN::Encode ':all';
use URI::Split qw(uri_split uri_join);
use HTML::Strip;
use HTML::Clean;
use Time::HiRes qw( time sleep );
use Try::Tiny; # on Debian/Ubuntu package libtry-tiny-perl


# to do : more subs
# correct path record ?


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


my (@urls, $url, %seen, %links_done, %hostnames, $finaluri, $clean_text, $confidence, $lang, $suspicious, $join, @redirect_candidates, $scheme, $auth, $path, $query, $frag);

my $todo = 'LINKS-TODO';
my $done = 'RESULTS-langid'; # may change
my $tocheck = 'LINKS-TO-CHECK';

my $errfile = 'ERRORS';
open (my $errout, ">>", $errfile) or die "Cannot open ERRORS file : $!\n";

my $logfile = 'LOG';
open (my $log, ">>", $logfile) or die "Cannot open LOG file : $!\n";

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
	my ($identifier, @tempurls);
	while (<$ltodo>) {
		chomp;
		# just in case
		next if (length($_) <= 10);
		next if ( ($_ =~ m/\.ogg$|\.mp3$|\.avi$|\.mp4$/) || ($_ =~ m/\.jpg$|\.JPG$|\.jpeg$|\.png$|\.gif$/) ); #pdf
		if (($_ =~ m/\.[a-z]+\/.+/) && (length($_) < 30)) {
			push (@redirect_candidates, $_);
		}
		else {
		($scheme, $auth, $path, $query, $frag) = uri_split($_); # problem : without query ?
		next if (($auth !~ m/\./) || ($scheme =~ m/^ftp/));
		my $red_uri = uri_join($scheme, $auth);
		my $ext_uri = uri_join($scheme, $auth, $path);
		# spare memory space
		$red_uri =~ s/^http:\/\///;
		$ext_uri =~ s/^http:\/\///;
		
		# find out if the url has already been stored
		if (defined $hostreduce) {
			if ((defined $identifier) && ($red_uri eq $identifier)) {
				push (@tempurls, $ext_uri);
			}
			else {
				## add a random url including the path (to get a better glimpse of the website)
				if (@tempurls) {
					%seen = ();
					@tempurls = grep { ! $seen{ $_ }++ } @tempurls;
					my $rand = int(rand(scalar(@tempurls)));
					push (@urls, $tempurls[$rand]);
					@tempurls = ();
				}
				unless (exists $links_done{$red_uri}) {
					push (@urls, $red_uri);
					$identifier = $red_uri;
				}
				else {
					$identifier = ();
				}
			}
		}
		else {
			unless (exists $links_done{$ext_uri}) {
				push (@urls, $ext_uri);
			}
		}
		}
	}
	#last one ?
	%seen = ();
	@redirect_candidates = grep { ! $seen{ $_ }++ } @redirect_candidates;
	close($ltodo);
}
else {
	die 'No todo list found under this file name: ' . $todo;
}

%seen = ();
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

my $stack = 0;
my $visits = 0;
my $i = 0;
my $suspcount = 0;
my $skip = 0;
open (my $out, '>>', $done);
open (my $check_again, '>>', $tocheck);

foreach $url (@urls) {
	# end the loop if the given number of urls was reached
	if (defined $links_count) {
		last if ($stack == $links_count);
	}

	# try to fetch and to send the page
	print $log $url . "\n";
	try {
		&fetch_url($url);
	}
	catch {
		if ($_ =~ m/no server/) {
			$skip = 1;
			last;
		}
		# catch and print all types of errors
		else {
			$_ =~ s/ at .+?\.$//;
			lock($errout);
			print $errout $_;
			unlock($errout);
		}
	};
	$hostnames{$url}++;
}

foreach $url (@redirect_candidates) {
	# end the loop if the given number of urls was reached
	if (defined $links_count) {
		last if ($stack == $links_count);
	}
	# end the loop if there is no server available
	last if ($skip == 1);

	# check redirection
	## found on http://stackoverflow.com/questions/2470053/how-can-i-get-the-ultimate-url-without-fetching-the-pages-using-perl-and-lwp
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
		$hostnames{$url}++;
		next;
	}
	
	# check
	if (defined $hostreduce) {
		($scheme, $auth, $path, $query, $frag) = uri_split($url);
		my $hostredux = uri_join($scheme, $auth);
		$hostredux =~ s/^http:\/\///;
		$url = $hostredux;
	}
	unless (exists $hostnames{$url}) { # also check links_done !
		# try to fetch and to send the page
		print $log $url . "\n";
		try {
			&fetch_url($url);
		}
		catch {
			if ($_ =~ m/no server/) {
				last;
			}
			# catch and print all types of errors
			else {
				$_ =~ s/ at .+?\.$//;
				lock($errout);
				print $errout $_;
				unlock($errout);
			}
		};
	$hostnames{$url}++;
	}
}


# SUBROUTINES

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

sub fetch_url {
	my $finaluri = shift;
	$stack++;
	unless ($finaluri =~ m/^http/) {
		$finaluri = "http://" . $finaluri; # consequence of sparing memory space
	}
	($scheme, $auth, $path, $query, $frag) = uri_split($finaluri);

	# time process
	## http://stackoverflow.com/questions/1165316/how-can-i-limit-the-time-spent-in-a-specific-section-of-a-perl-script
	## http://stackoverflow.com/questions/3427401/perl-make-script-timeout-after-x-number-of-seconds
	#{ no warnings 'exiting';
	try {
	local $SIG{ALRM} = sub { die "TIMEOUT\n" };
	alarm 30;

	# download, strip and put
	$req = HTTP::Request->new(GET => $finaluri);
	$req->header(
			'Accept' => 'text/html',
			'Accept-Encoding' => $can_accept,
		);
	# send request
  	$res = $ua->request($req);
	if ($res->is_success) {
		$visits++;
		# check the size of the page (to avoid a memory overflow)
		my $testheaders = $res->headers;
		if ($testheaders->content_length) {
			if ($testheaders->content_length > 500000) {
				alarm 0;
				die "Dropped (by content-size):\t" . $finaluri;
			}
		}
		my $body = $res->decoded_content(charset => 'none');

		{ no warnings 'uninitialized';
			if (length($body) < 100) { # could be another value
				alarm 0;
				die "Dropped (by body size):\t\t" . $finaluri;
			}
			my $h = new HTML::Clean(\$body);
			$h->strip();
			my $data = $h->data();

			my $hs = HTML::Strip->new();
			$clean_text = $hs->parse( $$data );
			$hs->eof;

			if (length($clean_text) < 100) { # could also be another value
				alarm 0;
				die "Dropped (by clean size):\t" . $finaluri;
			}
		}
	}
	} # end of try
	catch {
		if ($_ eq "TIMEOUT\n") {
			alarm 0;
			die "Handling timeout problem:\t" . $finaluri;
		}
		else {
			die $_;
		}
	};
	alarm 0;

	my $text = $clean_text;
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
			content	=> $text,
		);
	}
	catch {
		$text = encode('UTF-8', $text);
		try {
			( $minor_version, $code, $msg, $headers, $res ) = $furl->request(
				method  => 'PUT',
				host    => '78.46.186.58',
				port    => 9008,
				path_query => 'detect',
				content	=> $text,
			);
		}
		catch {
			alarm 0;
			die "ERROR: $@" . "\turl:\t" . $finaluri;
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
			$checkurl = $finaluri . "\t" . $lang . "\t" . $confidence;
			print $check_again $checkurl . "\n";
		}
		else {
			$i++;
			$output = $finaluri . "\t" . $lang . "\t" . $confidence;
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
			return "no server";
		}
	}
	else {
		die "Dropped (not found):\t" . $finaluri;
	}

	return;
} # end of subroutine


close($out);
close($check_again);
close($errout);
close($log);

splice(@urls, 0, $stack);
open (my $ltodo, '>', $todo);
print $ltodo join("\n", @urls);
close($ltodo);

my $total = scalar(@urls) + scalar(@redirect_candidates); # why doesn't it work ?
print "considered:\t" . $total . "\n";
print "tried:\t\t" . $stack . "\n";
print "visited:\t" . $visits . "\n";
print "positive:\t" . $i . "\n";
print "suspicious:\t" . $suspcount . "\n";
my $end_time = time();
print "execution time:\t" . sprintf("%.2f\n", $end_time - $start_time);