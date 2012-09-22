#!/usr/bin/perl


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use Getopt::Long;
use LWP::UserAgent;
use Fcntl qw(:flock SEEK_END);
require LWP::Protocol::https;
use IO::Socket::SSL;
use URI::Split qw(uri_split uri_join);
use Time::HiRes qw( time sleep );
use Try::Tiny; # on Debian/Ubuntu package libtry-tiny-perl
use Time::HiRes qw( time );


# TODO:
## threads


# command-line options
my ($help, $seen, $wholelist, $fileprefix, $filesuffix, $links_count, $timeout);
usage() if ( @ARGV < 1
	or ! GetOptions ('help|h' => \$help, 'timeout|t=i' => \$timeout, 'seen|s=s' => \$seen, 'fileprefix|fp=s' => \$fileprefix, 'filesuffix|fs=s' => \$filesuffix, 'all|a' => \$wholelist, 'links|l=i' => \$links_count)
	or defined $help
	or (defined $wholelist && defined $links_count)
);

sub usage {
	print "Unknown option: @_\n" if ( @_ );
	print "Usage: perl XX.pl [--help|-h] [--timeout|-t] [--seen|-s] [--fileprefix|-fp] prefix [--filesuffix|-fs] suffix [--all|-a] [--links|-l] number [--hostreduce|-hr] \n\n";
		print "timeout : timeout limit for the requests (default: 10)\n";
	print "seen : file containing the urls to skip\n";
	print "prefix : used to identify the files\n";
	print "EITHER --all OR a given number of links\n";
	exit;
}


# INITIALIZING
my $start_time = time();
if (!defined $timeout) {
	$timeout = 10;
}
## Agent here
my $agent = "Microblog-Explorer/0.2";
my ($req, $res);
my $ua = LWP::UserAgent->new; # another possibility : my $ua = LWPx::ParanoidAgent->new;
my $can_accept = HTTP::Message::decodable;
$ua->agent($agent);
$ua->timeout($timeout);


### redirection list, may not be exhaustive
my @redirection = ('t.co', 'j.mp', 'is.gd', 'wp.me', 'bit.ly', 'goo.gl', 'xrl.us', 'ur1.ca', 'b1t.it', 'dlvr.it', 'ping.fm', 'post.ly', 'p.ost.im', 'on.fb.me', 'tinyurl.com', 'friendfeed.com');
my ($redir_count, $positive, $negative) = (0) x 3;


## Files
### bound to change by command-line option
my $todo = 'LINKS-TODO';
open (my $ltodo, '<', $todo) or die "Cannot open LINKS-TODO file : $!\n";

my $errfile = 'red-ERRORS';
open (my $errout, ">>", $errfile) or die "Cannot open ERRORS file : $!\n";

my $done = 'REDIRECTS'; # may change
open (my $out_fh, '>>', $done) or die "Cannot open REDIRECTS file : $!\n";

my $norm = 'OTHERS'; # may change
open (my $norm_fh, '>>', $norm) or die "Cannot open OTHERS file : $!\n";



# MAIN LOOP
while (<$ltodo>) {
	# just in case : avoid possible traps
	next if (length($_) <= 10);
	next if ( ($_ =~ m/\.ogg$|\.mp3$|\.avi$|\.mp4$/) || ($_ =~ m/\.jpg$|\.JPG$|\.jpeg$|\.png$|\.gif$/) );
	next if ($_ =~ m/\.pdf$/);
	#if (defined $links_count) {
	#	last if ($stack == $links_count);
	#}
	my $url = $_;
	my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
	if ( ($auth ~~ @redirection) || (($_ =~ m/\.[a-z]+\/.+/) && (length($url) < 30)) ) {
		# check redirection
		$redir_count++;
		## found on http://stackoverflow.com/questions/2470053/how-can-i-get-the-ultimate-url-without-fetching-the-pages-using-perl-and-lwp
		$req = HTTP::Request->new(HEAD => $url);
		$req->header(
			'Accept' => 'text/html',
			'Accept-Encoding' => $can_accept,
		);
		$res = $ua->request($req);
		if ($res->is_success) {
			$url = $res->request()->uri();
			lock_and_write($out_fh, $url, $done);
			$positive++;
		}
		else {
			lock_and_write($errout, $url, $errfile);
			$negative++;
		}
	}
	else {
		lock_and_write($norm_fh, $url, $norm);
	}
}
close($ltodo);
close($out_fh);
close($norm_fh);
close($errout);


# Necessary if there are several threads
sub lock_and_write {
	my ($fh, $text, $filetype) = @_;
	chomp ($text);
	# http://perldoc.perl.org/functions/flock.html
	flock($fh, LOCK_EX) or die "Cannot lock " . $filetype . " file : $!\n";
	# in case something appended while we were waiting...
	seek($fh, 0, SEEK_END) or die "Cannot seek " . $filetype . " file : $!\n";
	print $fh $text . "\n" or die "Cannot write to " . $filetype . " file : $!\n";
	flock($fh, LOCK_UN) or die "Cannot unlock " . $filetype . " file : $!\n";
	return;
}


print "redirections number:\t" . $redir_count . "\n";
print "found:\t" . $positive . "\n";
print "not found:\t" . $negative . "\n";

my $end_time = time();
print "execution time:\t" . sprintf("%.2f\n", $end_time - $start_time);
