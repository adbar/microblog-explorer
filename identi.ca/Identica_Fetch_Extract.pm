#!/usr/bin/perl


###	This script is part of the Microblog-Explorer project (https://github.com/adbar/microblog-explorer).
###	Copyright (C) Adrien Barbaresi, 2012.
###	The Microblog-Explorer is freely available under the GNU GPL v3 license (http://www.gnu.org/licenses/gpl.html).


use strict;
use warnings;
use Furl; # supposed to be faster, must be installed through CPAN
require Compress::Zlib; # faster file transmission
# use utf8; use open ':encoding(utf8)'; doesn't seem to be necessary here
use URI::Split qw(uri_split uri_join);
# use Carp; for detailed error messages

package Identica_Fetch_Extract;
# export two functions/subroutines
use Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(&fetch &extract);

our $timeout = 5; # change this ?

my $furl = Furl::HTTP->new(
        agent   => 'Microblog-Explorer/0.1',
        timeout => $timeout,
	headers => [ 'Accept-Encoding' => 'gzip' ], # may run into problems (error to catch)
);


### Fetch the webpages
sub fetch {
	my $path = shift;
	$path =~ s/^\/+//;
	my ($minor_version, $code, $msg, $headers, $body) = $furl->request(
		method     => 'GET',
		host       => 'identi.ca',
		port       => 80,
		path_query => $path
	);
	return ($code, $msg, $body);
}


### Extract the external and internal links
sub extract {
	my $html = shift;
	my (@ext, @int);
	## EXTERNAL LINKS
	my @links = split ("<a href=\"", $html);
	splice (@links, 0, 1);
	foreach my $link (@links) {
		unless ($link =~ m/http:\/\/www.geonames.org\//) {
			if ( ($link =~ m/rel="nofollow external">/) || ($link =~ m/rel="external">/) ) {
				$link =~ m/title="(.+?)"/;
				if (defined $1) {
					unless ($1 =~ m/^[0-9]/) {
					unless ($1 =~ m/\.jpg$|\.JPG$|\.jpeg$|\.png$|\.gif$|\.pdf$/) {
					unless ($1 =~ m/\.ogg$|\.mp3$|\.avi$|\.mp4$/) {
						my $temp = $1;
						# delete bad hostnames and eventual query parameters :
						my ($scheme, $auth, $path, $query, $frag) = URI::Split::uri_split($temp);
						{ no warnings 'uninitialized';
							next if (length($auth) < 5);
							$temp = URI::Split::uri_join($scheme, $auth, $path);
						}
						$temp = lc($temp);
						push (@ext, $temp);
					}}}
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
	}
	} # end of warnings
	return (\@ext, \@int);
}

1;