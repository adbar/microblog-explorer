#!/usr/bin/perl


###	This script is part of the microblog-explorer project (https://github.com/adbar/microblog-explorer).
###	It is brought to you by Adrien Barbaresi.
###	It is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use Furl; # supposed to be faster, must be installed through CPAN
#use utf8; use open ':encoding(utf8)'; doesn't seem to be necessary here
use URI::Split qw(uri_split uri_join);
use threads;
use threads::shared;
use Time::HiRes qw( time sleep );


die 'Usage: perl XX.pl [number of links to scan]' if (scalar (@ARGV) != 1);
my $ucount = $ARGV[0];
my $sleepfactor = 3; # 2.5 worked

my ($path, @users, %users_done);
my (@ushared, @external, @internal, @done, $seen_users, $errors, $nreq, @errurls) :shared;
$seen_users = 0;
$errors = 0;
$nreq = 0;

my $userslist = 'USERS_TODO';
my $usersdone = 'USERS_DONE';

if (-e $usersdone) {
	open (my $udone, '<', $usersdone);
	while (<$udone>) {
		$_ =~ m/(^[A-Za-z0-9]+)/;
		$users_done{$1}++;
	}
	close($udone);
}

if (-e $userslist) {
	open (my $ulist, '<', $userslist);
	while (<$ulist>) {
		chomp;
		unless (exists $users_done{$_}) {
			push (@users, $_);	
		}
	}
	close($ulist);
}
else {
	die 'no todo list';
}

my $start_time = time();

my $furl = Furl::HTTP->new(
        agent   => 'Microblog-Explorer-0.1',
        timeout => 6, # 5 worked
	headers => [ 'Accept-Encoding' => 'gzip' ], # may run into problems (error to catch)
);

my %seen = ();
@users = grep { ! $seen{ $_ }++ } @users;
my @temp = splice (@users, 0, $ucount);

my $divide = int(scalar(@temp)/4);
my @thr1 = splice (@temp, 0, $divide);
my @thr2 = splice (@temp, 0, $divide);
my @thr3 = splice (@temp, 0, $divide);
my @thr4 = @temp;


## Threads

my $throne = threads->create(\&thread, @thr1);
my $thrtwo = threads->create(\&thread, @thr2);
my $thrthree = threads->create(\&thread, @thr3);
my $thrfour = threads->create(\&thread, @thr4);

sub thread {
	my @list = @_;
	foreach my $intlink (@list) {
		%seen = ();
		@internal = grep { ! $seen{ $_ }++ } @internal; # free some memory space
		# timeline
		my $page = fetch($intlink);
		my ($ext, $int) = extract($page);
		push (@external, @$ext) if defined @$ext;
		push (@internal, @$int) if defined @$int;
		if ($page =~ m/<dl class="entity_notices">(.+?)<\/dl>/s) {
			my $max = $1;
			$max =~ m/<dd>([0-9]+)<\/dd>/;
			$max = int($1/20);
			$max++;
			if ($max > 20) { # 100 was too much
				$max = 20;
			}
			unless ($max == 1) {
				for (my $n = 2; $n <= $max; $n++) {
					my $htmlerr = 0;
					$page = fetch($intlink . "?page=" . $n);
					$htmlerr++ if ($page eq "ERR");
					last if $htmlerr > 3;
					($ext, $int) = extract($page);
					push (@external, @$ext) if defined @$ext;
					push (@internal, @$int) if defined @$int;
					sleep ($sleepfactor);
				}
			}
			push (@done, $intlink . "\t" . $max);
		}
		# following
		if ($page =~ m/<a href="http:\/\/identi.ca\/[A-Za-z0-9]+?\/subscriptions" class="">[A-Za-z]+?<\/a>.+?([0-9]+?)<\/h2>/s) {
			$seen_users += $1;
			my $max = int($1/20);
			$max++;
			if ($max > 20) { # 100 was too much
				$max = 20;
			}
			for (my $n = 1; $n <= $max; $n++) {
				my $htmlerr = 0;
				my $suscr = fetch($intlink . "/subscriptions?page=" . $n);
				$htmlerr++ if ($page eq "ERR");
				last if $htmlerr > 3;
				($ext, $int) = extract_users($suscr);
				push (@external, @$ext) if defined @$ext;
				push (@ushared, @$int) if defined @$int;
				sleep($sleepfactor);
			}
		}
		#followers
		if ($page =~ m/<a href="http:\/\/identi.ca\/[A-Za-z0-9]+?\/subscribers" class="">[A-Za-z]+?<\/a>.+?([0-9]+?)<\/h2>/s) {
			$seen_users += $1;
			my $max = int($1/20);
			$max++;
			if ($max > 20) { # 100 was too much
				$max = 20;
			}
			for (my $n = 1; $n <= $max; $n++) {
				my $htmlerr = 0;
				my $suscr = fetch($intlink . "/subscribers?page=" . $n);
				$htmlerr++ if ($page eq "ERR");
				last if $htmlerr > 3;
				($ext, $int) = extract_users($suscr);
				push (@external, @$ext) if defined @$ext;
				push (@ushared, @$int) if defined @$int;
				sleep($sleepfactor);
			}
		}
	}
}

$throne->join();
$thrtwo->join();
$thrthree->join();
$thrfour->join();

print "requests:\t" . $nreq . "\n";
print "seen users:\t" . $seen_users . "\n";
print "errors:\t\t" . $errors . "\n";
my $inttotal = scalar (@internal);
my $exttotal = scalar (@external);

### CLEANING AND WRITEDOWN
# fast removal of duplicates
%seen = ();
@external = grep { ! $seen{ $_ }++ } @external;
%seen = ();
@internal = grep { ! $seen{ $_ }++ } @internal;
my @users_todo = (@users, @ushared);
%seen = ();
@users_todo = grep { ! $seen{ $_ }++ } @users_todo;

print "total int:\t" . scalar (@internal) . "\n";
print "total ext:\t" . scalar (@external) . "\t(uniqueness ratio: " . sprintf("%.1f", $exttotal/scalar (@external)) . ")\n";

open (my $resultint, '>>', 'ld-int');
print $resultint join("\n", @internal);
close($resultint);

open (my $resultext, '>>', 'ld-ext');
print $resultext join("\n", @external);
close($resultext);

open (my $errurls, '>>', 'ld-errurls');
print $errurls join("\n", @errurls);
close($errurls);

open (my $usdone, '>>', $usersdone);
print $usdone join("\n", @done);
close($usdone);

open (my $uslist, '>', $userslist);
print $uslist join("\n", @users_todo);
close($uslist);


my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);


### SUBS

sub fetch {
	my $path = shift;
	#if ($path !~ m/^\//) {
	#	$path = "/" . $path;
	#}
	$path =~ s/^\/+//;
	my ($minor_version, $code, $msg, $headers, $body) = $furl->request(
		method     => 'GET',
		host       => 'identi.ca',
		port       => 80,
		path_query => $path
	);
	unless ($msg eq "OK") {
		$errors++;
		$body = "ERR";
		my $buffer = $path . "\t" . $code . "\t" . $msg;
		push (@errurls, $buffer);
	}
	$nreq++;
	return $body;
}

sub extract {
	my $html = shift;
	my (@ext, @int);
	unless ($html eq "ERR") {
	## EXTERNAL LINKS
	my @links = split ("<a href=\"", $html);
	splice (@links, 0, 1);
	foreach my $link (@links) {
		unless ($link =~ m/http:\/\/www.geonames.org\//) {
			if ( ($link =~ m/rel="nofollow external">/) || ($link =~ m/rel="external">/) ) {
				$link =~ m/title="(.+?)"/;
				if (defined $1) {
					unless ( ($1 =~ m/gif|png|jpg|jpeg$/) || ($1 =~ m/^[0-9]/) ) {
						my $temp = $1;
						#$temp =~ s/\?utm_.*$//; # may not cover all the cases
						# suppression of bad hostnames and eventual query parameters :
						my ($scheme, $auth, $path, $query, $frag) = uri_split($temp);
						next if (length($auth) < 5);
						$temp = uri_join($scheme, $auth, $path);
						$temp = lc($temp);
						push (@ext, $temp);
					}
				}
			}
		}
	}

	## INTERNAL LINKS
	# ids, groups
	@links = split ("<span class=\"vcard", $html);
	splice (@links, 0, 1);
	foreach my $link (@links) {
		if ($link =~ m/<a href="http:\/\/identi.ca\/(.+?)"/) {
			if (defined $1) {
				push (@int, $1) unless ( ($1 =~ m/^attachment|conversation|favorited|featured|api/) || ($1 =~ m/^[^a-z]/) );
			}
		}
	}
	# tags
	{ no warnings 'uninitialized';
	@links = split ("<span class=\"tag\">", $html);
	splice (@links, 0, 1);
	foreach my $link (@links) {
		if ($link =~ m/<a href="http:\/\/identi.ca\/(.+?)"/) {
			if (defined $1) {
				push (@int, $1) unless ( ($1 =~ m/^api/) || ($1 =~ m/^[^a-z]/) );
			}
		}
	}} #end of unless
	}
	return (\@ext, \@int);
}

sub extract_users {
	my $html = shift;
	my (@ext, @users);
	unless ($html eq "ERR") {
		## Users links
		my @links = split ("<a href=\"", $html);
		splice (@links, 0, 1);
		foreach my $link (@links) {
			if ($link =~ m/^http:\/\/identi.ca\/([A-Za-z0-9]+?)" class="url entry-title" rel="nofollow">(.+?)<\/a>/) {
				push (@users, $1);
				push (@ext, $2);
			}
		}
	}
	return (\@ext, \@users);
}
