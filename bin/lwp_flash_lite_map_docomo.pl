#!/usr/bin/perl

use strict;
use warnings;
use Jcode;
use LWP::Simple qw();

my $URL = 'http://www.nttdocomo.co.jp/p_s/imode/spec/flash.html';

do_task(@ARGV);

sub do_task {
	my $html = Jcode->new(LWP::Simple::get($URL))->euc;
	$html =~ s/\r//g;
	$html =~ s/\s*\n+/\n/g;

	my $re = regexp_ver() ;

	my @flash;
	{
		my $re = regexp_model();
		while ($html =~ /$re/igs) {
			push(@flash, {
				model          => uc $1,
				width          => $2,
				height         => $3,
				max_file_size  => $4,
			});
		}
	}

	{
		my $re = regexp_ver();
		while ($html =~ /$re/igs) {
			my($count, $version) = ($1, $2);
			my $i = 1;
			for my $f (@flash) {
				last if ($i > $count);
				unless ($f->{version}) {
					$i++;
					$f->{version} = $version;
				}
			}
		}
	}

	for my $f (@flash) {
		printf "%s:\n", $f->{model};
		for my $key (qw(version width height max_file_size)) {
			printf "  %s : %s\n", $key, $f->{$key};
		}
	}
}

sub regexp_model {
	return <<'REGEX';
<TD><FONT SIZE="2">([A-Z]+\d+\w*).*?</FONT></TD>
<TD><FONT SIZE="2">(\d+)¡ß(\d+)</FONT></TD>
<TD><FONT SIZE="2">.+?</FONT></TD>
<TD><FONT SIZE="2">(\d+)</FONT></TD>
<TD><FONT SIZE="2">.+?</FONT></TD>
<TD><FONT SIZE="2">.+?</FONT></TD>
REGEX
}

sub regexp_ver {
	return <<'REGEX';
<TR ALIGN="CENTER" BGCOLOR="#FFFFFF">
<TD rowspan="(\d+)" BGCOLOR="#FFFFCC"><FONT SIZE="2" COLOR="#009900">(\d+.\d+)</FONT></TD>
<TD rowspan="\d+" BGCOLOR="#FFFFCC"><FONT SIZE="2" COLOR="#009900">\w+</FONT></TD>
REGEX
}
