#!/usr/bin/perl


###	This script is part of the microblog-explorer project (https://github.com/adbar/microblog-explorer).
###	It is brought to you by Adrien Barbaresi.
###	It is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use Furl; # supposed to be faster, must be installed through CPAN
#use utf8; use open ':encoding(utf8)'; doesn't seem to be necessary here
use threads;
use threads::shared;
use Time::HiRes qw( time );

my $start_time = time();

# -> problems with timeout

my $furl = Furl::HTTP->new(
        agent   => 'Perl-Furl',
        timeout => 5,
	headers => [ 'Accept-Encoding' => 'gzip' ], # may run into problems (error to catch)
);

my ($path, %hsp, @int_explore);
my (@external, @internal, $errors, @errurls, $nreq, @daily_spare, @hourly_spare, %daily_spare) :shared;
$errors = 0;
$nreq = 0;

## load spare lists

my $hsplist = 'hourly_spare';
my $dsplist = 'daily_spare';

if (-e $hsplist) {
	open (my $hsp, '<', $hsplist);
	while (<$hsp>) {
		$hsp{$_}++;
	}
	close($hsp);
}

if (-e $dsplist) {
	open (my $dsp, '<', $dsplist);
	while (<$dsp>) {
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
		my $page = fetch($path);
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
	foreach my $intlink (@list) {
		my $page = fetch($intlink);
		my ($ext, $int) = extract($page);
		push (@external, @$ext) if defined @$ext;
		push (@internal, @$int) if defined @$int;
		## spare tags and users who don't tweet often
		if ($intlink =~ m/^tag\//) {
			(push @hourly_spare, $intlink);
		}
		if ($page =~ m/<dl class="entity_daily_notices">(.+?)<\/dl>/s) {
			my $mean = $1;
			$mean =~ m/<dd>([0-9]+)<\/dd>/;
			$mean = $1;
			if ($mean <= 5) {
				$daily_spare{$intlink}++;
			}
			if ( ($mean > 5) && ($mean <= 20) ) {
				(push @hourly_spare, $intlink);
			}
		}
	}
}

$throne->join();
$thrtwo->join();
$thrthree->join();
$thrfour->join();

print "requests:\t" . $nreq . "\n";
print "errors:\t\t" . $errors . "\n";
my $inttotal = scalar (@internal);
my $exttotal = scalar (@external);

### CLEANING AND WRITEDOWN
# fast removal of duplicates
%seen = ();
@external = grep { ! $seen{ $_ }++ } @external;
%seen = ();
@internal = grep { ! $seen{ $_ }++ } @internal;

print "total int:\t" . scalar (@internal) . "\t(uniqueness ratio: " . sprintf("%.1f", $inttotal/scalar (@internal)) . ")\n";
print "total ext:\t" . scalar (@external) . "\t(uniqueness ratio: " . sprintf("%.1f", $exttotal/scalar (@external)) . ")\n";

open (my $resultint, '>>', 'result-int');
print $resultint join("\n", @internal);
close($resultint);

open (my $resultext, '>>', 'result-ext');
print $resultext join("\n", @external);
close($resultext);

open (my $errurls, '>>', 'errurls');
print $errurls join("\n", @errurls);
close($errurls);

open (my $hspare, '>', 'hourly_spare');
print $hspare join("\n", @hourly_spare);
close($hspare);

open (my $dspare, '>', 'daily_spare');
foreach my $k (keys %daily_spare) {
	print $dspare $k . "\n";
}
close($dspare);

my $end_time = time();
print "execution time: " . sprintf("%.2f\n", $end_time - $start_time);


### SUBS

sub fetch {
	my $path = shift;
	if ($path !~ m/^\//) {
		$path = "/" . $path;
	}
	my ($minor_version, $code, $msg, $headers, $body) = $furl->request(
		method     => 'GET',
		host       => 'identi.ca',
		port       => 80,
		path_query => $path
	);
	unless ($msg eq "OK") {
		$errors++;
		$body = "ERR";
		push (@errurls, $path);
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
						$temp =~ s/(?|&amp;)utm_.*$//;
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