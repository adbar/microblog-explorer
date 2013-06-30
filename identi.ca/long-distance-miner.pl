#!/usr/bin/perl


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw( time sleep );
use Identica_Fetch_Extract qw( fetch extract );


## EXAMPLE:
# (perl long-distance-miner.pl 50 &> ld-log &)


## Expects a number as argument
die 'Usage: perl XX.pl [number of links to scan]' if (scalar (@ARGV) != 1);
die 'Usage: perl XX.pl [number of links to scan] -- argument must be an integer' unless ($ARGV[0] =~ /^-?\d+$/);
my $ucount = $ARGV[0];

## Change the time between two pages in the same thread here
my $sleepfactor = 3;
# 5 sec timeout by default

my $depthlimit = 20; # 100 was too much

my ($path, @users, %users_done);
my (@ushared, @external, @internal, @done, $seen_users, $nreq, @errurls) :shared;
$seen_users = 0;
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

my (%seen, @temp);
@users = grep { ! $seen{ $_ }++ } @users;
if ($ucount < scalar(@users)) {
	@temp = splice (@users, 0, $ucount);
}
else {
	@temp = @users;
}

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
		{ no warnings 'uninitialized';
			@internal = grep { ! $seen{ $_ }++ } @internal; # free some memory space
		}
		# fetch page
		my ($code, $msg, $page) = fetch($intlink);
		$nreq++;
		unless ($msg eq "OK") {
			my $buffer = $intlink . "\t" . $code . "\t" . $msg;
			push (@errurls, $buffer);
			next;
		}
		# process timeline
		my ($ext, $int) = extract($page);
		push (@external, @$ext) if defined @$ext;
		push (@internal, @$int) if defined @$int;
		if ($page =~ m/<dl class="entity_notices">(.+?)<\/dl>/s) {
			my $max = $1;
			$max =~ m/<dd>([0-9]+)<\/dd>/;
			$max = int($1/20);
			$max++;
			$max = $depthlimit if ($max > $depthlimit);
			unless ($max == 1) {
				my $htmlerr = 0;
				for (my $n = 2; $n <= $max; $n++) {
					$page = fetch($intlink . "?page=" . $n);
					$nreq++;
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
			$max = $depthlimit if ($max > $depthlimit);
			&follow_expl($intlink, "/subscriptions?page=", $max);
		}
		#followers
		if ($page =~ m/<a href="http:\/\/identi.ca\/[A-Za-z0-9]+?\/subscribers" class="">[A-Za-z]+?<\/a>.+?([0-9]+?)<\/h2>/s) {
			$seen_users += $1;
			my $max = int($1/20);
			$max++;
			$max = $depthlimit if ($max > $depthlimit);
			&follow_expl($intlink, "/subscribers?page=", $max);
		}
	}
}

$throne->join();
$thrtwo->join();
$thrthree->join();
$thrfour->join();

print "requests:\t" . $nreq . "\n";
print "seen users:\t" . $seen_users . "\n";
print "errors:\t\t" . scalar(@errurls) . "\n";
my $inttotal = scalar (@internal);
my $exttotal = scalar (@external);


### CLEANING AND WRITEDOWN
# fast removal of duplicates
%seen = ();
@external = grep { ! $seen{ $_ }++ } @external;
%seen = ();
@internal = grep { ! $seen{ $_ }++ } @internal; # uninitialized problem : empty internal list ?
my @users_todo = (@users, @ushared);
%seen = ();
@users_todo = grep { ! $seen{ $_ }++ } @users_todo;

print "total int:\t" . scalar (@internal) . "\n"; # uninitialized problem : empty internal list ?
print "total ext:\t" . scalar (@external) . "\t(uniqueness ratio: " . sprintf("%.1f", $exttotal/scalar (@external)) . ")\n";

writefile('ld-int', '>>', \@internal);
writefile('ld-ext', '>>', \@external);
writefile('ld-errurls', '>>', \@errurls);

open (my $usdone, '>>', $usersdone);
print $usdone join("\n", @done);
close($usdone);

open (my $uslist, '>', $userslist);
print $uslist join("\n", @users_todo);
close($uslist);


my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);


### SUBROUTINES

sub follow_expl {
	my ($link, $append, $max) = @_;
	my $htmlerr = 0;
	for (my $n = 1; $n <= $max; $n++) {
		my $address = $link . $append . $n;
		my ($code, $msg, $page) = fetch($address);
		$nreq++;
		unless ($msg eq "OK") {
			my $buffer = $link . "\t" . $code . "\t" . $msg;
			push (@errurls, $buffer);
			$htmlerr++;
		}
		last if $htmlerr > 3;
		my ($ext, $int) = extract_users($address);
		push (@external, @$ext) if defined @$ext;
		push (@ushared, @$int) if defined @$int;
		sleep($sleepfactor);
	}
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
