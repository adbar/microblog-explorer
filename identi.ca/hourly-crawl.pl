#!/usr/bin/perl


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw( time sleep );
use Cwd;
my $directory = cwd;
use lib $directory;
use Identica_Fetch_Extract qw( fetch extract );


my $start_time = time();

## Change the time between two pages in the same thread here
my $sleepfactor = 0.5;
# 5 sec timeout by default

my ($path, %hsp, @int_explore, %daily_spare, @hourly_spare);
my (@external, @internal, @errurls, $nreq) :shared;
$nreq = 0;

## load spare lists

my $hsplist = $directory . '/hourly_spare';
my $dsplist = $directory . '/daily_spare';

if (-e $hsplist) {
	open (my $hsp, '<', $hsplist);
	while (<$hsp>) {
		chomp;
		$hsp{$_}++;
	}
	close($hsp);
}

if (-e $dsplist) {
	open (my $dsp, '<', $dsplist);
	while (<$dsp>) {
		chomp;
		$daily_spare{$_}++;
	}
	close($dsp);
}

## initial page
my $indexone = threads->create(\&indexthr, (1,5));
my $indextwo = threads->create(\&indexthr, (6,10));
my $indexthree = threads->create(\&indexthr, (11,15));

sub indexthr {
	my @list = @_;
	for (my $n = $list[0]; $n <= $list[1]; $n++) {
		$path = "/?page=" . $n;
		my ($code, $msg, $page) = fetch($path);
		$nreq++;
		unless ($msg eq "OK") {
			my $buffer = $path . "\t" . $code . "\t" . $msg;
			push (@errurls, $buffer);
			next;
		}
		my ($ext, $int) = extract($page);
		push (@external, @$ext);
		push (@internal, @$int);
	}
}

$indexone->join();
$indextwo->join();
$indexthree->join();

# fast removal of duplicates
my %seen = ();
@internal = grep { ! $seen{ $_ }++ } @internal;

# filtering
foreach my $link (@internal) {
	#if ($link !~ m/^tag\//) {
		unless (exists $daily_spare{$link}) {
			unless (exists $hsp{$link}) {
				push (@int_explore, $link);
			}
		}
	#}
}

# adjust sleeping time if the list seems long
if (scalar(@int_explore) > 200) {
	$sleepfactor *= 3;
}

## internal links
print "index int:\t" . scalar (@internal) . "\n";
print "int explore:\t" . scalar (@int_explore) . "\n";
print "index ext:\t" . scalar (@external) . "\n";
my $divide = int(scalar(@int_explore)/4);
my @thr1 = splice (@int_explore, 0, $divide);
my @thr2 = splice (@int_explore, 0, $divide);
my @thr3 = splice (@int_explore, 0, $divide);
my @thr4 = @int_explore;


## Threads

my $throne = threads->create(\&thread, @thr1);
my $thrtwo = threads->create(\&thread, @thr2);
my $thrthree = threads->create(\&thread, @thr3);
my $thrfour = threads->create(\&thread, @thr4);

sub thread {
	my @list = @_;
	my (@daily_spare, @h_spare);
	foreach my $intlink (@list) {
		# fetch page
		my ($code, $msg, $page) = fetch($intlink);
		$nreq++;
		unless ($msg eq "OK") {
			my $buffer = $intlink . "\t" . $code . "\t" . $msg;
			push (@errurls, $buffer);
			next;
		}
		my ($ext, $int) = extract($page);
		push (@external, @$ext) if defined @$ext;
		push (@internal, @$int) if defined @$int;
		## spare tags and users who don't tweet often
		if ($intlink =~ m/^tag\//) {
			(push @h_spare, $intlink);
		}
		if ($page =~ m/<dl class="entity_daily_notices">(.+?)<\/dl>/s) {
			my $mean = $1;
			$mean =~ m/<dd>([0-9]+)<\/dd>/;
			$mean = $1;
			if ($mean <= 5) {
				push (@daily_spare, $intlink);
			}
			if ( ($mean > 5) && ($mean <= 25) ) {
				(push @h_spare, $intlink);
			}
		}
		sleep ($sleepfactor);
	}
	return (\@daily_spare, \@h_spare);
}

# could be shorter... (subroutine ?)
my ($ds, $hs) = $throne->join();
@daily_spare{@$ds} = () if defined @$ds;
push (@hourly_spare, @$hs) if defined @$hs;

($ds, $hs) = $thrtwo->join();
@daily_spare{@$ds} = () if defined @$ds;
push (@hourly_spare, @$hs) if defined @$hs;

($ds, $hs) = $thrthree->join();
@daily_spare{@$ds} = () if defined @$ds;
push (@hourly_spare, @$hs) if defined @$hs;

($ds, $hs) = $thrfour->join();
@daily_spare{@$ds} = () if defined @$ds;
push (@hourly_spare, @$hs) if defined @$hs;

print "requests:\t" . $nreq . "\n";
print "errors:\t\t" . scalar(@errurls) . "\n";
my $inttotal = scalar (@internal);
my $exttotal = scalar (@external);

### CLEANING AND WRITEDOWN
# fast removal of duplicates
%seen = ();
@external = grep { ! $seen{ $_ }++ } @external;
%seen = ();
@internal = grep { ! $seen{ $_ }++ } @internal;

if (@internal) {
	print "total int:\t" . scalar (@internal) . "\t(uniqueness ratio: " . sprintf("%.1f", $inttotal/scalar (@internal)) . ")\n";
}
else {
	print "No internal links.\n";
}
if (@external) {
	print "total ext:\t" . scalar (@external) . "\t(uniqueness ratio: " . sprintf("%.1f", $exttotal/scalar (@external)) . ")\n";
}
else {
	print "No external links.\n";
}


# write down the files
sub writefile {
	my ($filename, $type, $array) = @_;
	open (my $fh, $type, $filename);
	print $fh join("\n", @{$array});
	close($fh);
	return;
}

writefile($directory . '/result-int', '>>', \@internal);
writefile($directory . '/result-ext', '>>', \@external);
writefile($directory . '/errurls', '>>', \@errurls);

%seen = ();
@hourly_spare = grep { ! $seen{ $_ }++ } @hourly_spare;
writefile($directory . '/hourly_spare', '>', \@hourly_spare);

open (my $dspare, '>', $directory . '/daily_spare');
print $dspare join("\n", keys %daily_spare);
close($dspare);

my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);
