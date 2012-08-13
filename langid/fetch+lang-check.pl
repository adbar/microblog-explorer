#!/usr/bin/perl


###	This script is part of the microblog-explorer project (https://github.com/adbar/microblog-explorer).
###	It is brought to you by Adrien Barbaresi.
###	It is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).

# This script is to be used in combination with a language identification system (https://github.com/saffsd/langid.py) running as a server on port 9008. Please adjust the host parameter to your configuration (see below).


use strict;
use warnings;
use open ':encoding(utf8)';
use Encode qw(encode);
use Furl;
use LWP::UserAgent;
use IO::Socket::SSL;
use Net::IDN::Encode ':all';
use URI::Split qw(uri_split uri_join);
use HTML::Strip;
use HTML::Clean;
use threads;
use threads::shared;
use Time::HiRes qw( time );


die 'Usage: perl XX.pl [number of links to scan]' if (scalar (@ARGV) != 1);
my $links_count = $ARGV[0];

my @output :shared;
my (@urls, @done, %links_done, %hostnames, $finaluri);

my $linkstodo = 'LINKS_TODO';
my $linksdone = 'LINKS_DONE';

if (-e $linksdone) {
	open (my $ldone, '<', $linksdone);
	while (<$ldone>) {
		chomp;
		$links_done{$_}++;
		my ($scheme, $auth, $path, $query, $frag) = uri_split($_);
		my $temp = lc(uri_join($scheme, $auth));
		$hostnames{$temp}++;
	}
	close($ldone);
}

if (-e $linkstodo) {
	open (my $ltodo, '<', $linkstodo);
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
my @temp = splice (@urls, 0, $links_count); # lots of RAM wasted for the remaining urls

my $start_time = time();

my @redirection = ('t.co', 'j.mp', 'is.gd', 'wp.me', 'bit.ly', 'goo.gl', 'xrl.us', 'ur1.ca', 'b1t.it', 'dlvr.it', 'ping.fm', 'post.ly', 'on.fb.me', 'tinyurl.com');

my $furl = Furl::HTTP->new(
        agent   => 'Microblog-Explorer-0.1',
        timeout => 5,
	headers => [ 'Accept-Encoding' => 'gzip' ],  # may run into problems (error to catch)
);

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;
$ua->agent("Microblog-Explorer-0.1");
$ua->timeout( 5 );


## Threads
my $i = 0;
open (my $out, '>>', 'RESULTS_langid');

foreach my $url (@temp) {

	# check redirection
	$url =~ m/https?:\/\/(.+?)\//;
	my $short = $1;
	if ($short ~~ @redirection) {
		# found on  http://stackoverflow.com/questions/2470053/how-can-i-get-the-ultimate-url-without-fetching-the-pages-using-perl-and-lwp
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
	my $finaluri = lc(uri_join($scheme, $auth));
	if (exists $hostnames{$finaluri}) {
		next;
	}
	else {
		$hostnames{$finaluri}++;
	}

	push (@done, $finaluri);

	# download, strip and put
	my $body = $furl->get($finaluri);
	$i++;
	my $h = new HTML::Clean(\$body);
	$h->strip();
	my $data = $h->data();

	my $hs = HTML::Strip->new();
	my $clean_text = $hs->parse( $$data );
	$hs->eof;

	$clean_text = encode('UTF-8', $clean_text);

	my ( $minor_version, $code, $msg, $headers, $res ) = $furl->request(
		method  => 'PUT',
		host    => '*.*.*.*', # please fill this out
		port    => 9008,
		path_query => 'detect',
		content	=> $clean_text,
	);
	if ($code == 200) {
		$res =~ m/"confidence": (.+?), "language": "([a-z]+?)"/;
		my $output = $finaluri . "\t" . $2 . "\t" . $1;
		print $out $output . "\n";
	}
}

close($out);

open (my $ldone, '>', 'LINKS_DONE');
print $ldone join("\n", @done);
close($ldone);


open (my $ltodo, '>', 'LINKS_TODO');
print $ltodo join("\n", @urls);
close($ltodo);

print "urls: " . $links_count . "\n";
print "visited: " . $i . "\n";
my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);
