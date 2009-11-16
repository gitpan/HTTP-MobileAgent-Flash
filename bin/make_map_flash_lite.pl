#!/usr/bin/perl

use strict;
use warnings;

use HTTP::MobileAgent;

use WWW::MobileCarrierJP::DoCoMo::Flash;
use WWW::MobileCarrierJP::EZWeb::DeviceID;
use WWW::MobileCarrierJP::EZWeb::Model;
use WWW::MobileCarrierJP::ThirdForce::Service;
use WWW::MobileCarrierJP::ThirdForce::HTTPHeader;
use WWW::MobileCarrierJP::ThirdForce::UserAgent;

use Getopt::Long;
use Pod::Usage;
use Data::Dumper;

our $PROGNAME = ($0 =~ /(\w+\.pl)$/)[0];
our $OPTION   = join( ' ', @ARGV);

our $MESSAGE = <<"...";
# -------------------------------------------------------------------------
# This file is autogenerated by $PROGNAME
# in HTTP::MobileAgent::Flash distribution.
#
# $PROGNAME $OPTION
# -------------------------------------------------------------------------
...

our $MODULE_TMPL = <<'...';
package {{MODULE_NAME}};
{{MESSAGE}}
use strict;
use warnings;

require Exporter;
use base qw(Exporter);
our @EXPORT_OK = qw($FLASH_MAP);
our $FLASH_MAP;

BEGIN {
    if ($ENV{{{ENV_FLASH_MAP}}}) {
        eval q{
            require YAML::Syck;
            $FLASH_MAP = YAML::Syck::LoadFile($ENV{{{ENV_FLASH_MAP}}});
        };
        if ($@) {
            eval q{
                require YAML;
                $FLASH_MAP = YAML::LoadFile($ENV{{{ENV_FLASH_MAP}}});
            };
        }
        warn "using normal hash map: $@" if $@;
    }
}
...

our $OUTPUT_TYPE    = 'pm';
our $SCRAPE_CARRIER = '';
our $HELP = '0';

GetOptions(
    'output=s'  => \$OUTPUT_TYPE,
    'carrier=s' => \$SCRAPE_CARRIER,
    'help|?'    => \$HELP,
)  or pod2usage(2);


pod2usage(1) if $HELP;

my $map;
if    ($SCRAPE_CARRIER eq 'docomo')   { $map = make_map_docomo()   }
elsif ($SCRAPE_CARRIER eq 'ezweb')    { $map = make_map_ezweb()    }
elsif ($SCRAPE_CARRIER eq 'softbank') { $map = make_map_softbank() }
else { pod2usage(2) }

if    ($OUTPUT_TYPE eq 'pm' )   { output_pm($map)   }
elsif ($OUTPUT_TYPE eq 'yaml' ) { output_yaml($map) }
else                            { pod2usage(2)      }

sub make_map_docomo {

    # {
    #     version => '1.0'
    #     models => [
    #         {
    #             model => 'D505I'
    #             standby_screen => { width => '240', height => '320'},
    #             browser        => [ 
    #                 {width   => '240', 'height' => '270'},
    #             ],
    #             working_memory_capacity => '200',
    #         },
    #         :
    #     }
    # },
    # {
    #     version => '1.1',
    #     :
    # },
    my $data = WWW::MobileCarrierJP::DoCoMo::Flash->scrape();

    my $flash_map;
    for my $version (@$data) {
        for my $model (@{$version->{models}}) {
            $flash_map->{ $model->{model} } = {
                version => $version->{version},
                width   => $model->{standby_screen}->{width}  || $model->{browser}->[0]->{width},
                height  => $model->{standby_screen}->{height} || $model->{browser}->[0]->{height},
                max_file_size => $model->{working_memory_capacity},
            }
        }
    }

    return $flash_map;
}

sub make_map_ezweb {
    # $device_map
    # W32S => {
    #     device_id => [SN33, SN35],
    # },
    my $device_map = +{ map { $_->{model} => {device_id => $_->{device_id}} } @{ WWW::MobileCarrierJP::EZWeb::DeviceID->scrape() } };

    for my $model (@{WWW::MobileCarrierJP::EZWeb::Model->scrape()}) {
        my $model_long = $model->{model_long};
        # HTTP::MobileAgent::EZweb::is_win
        # http://www.au.kddi.com/ezfactory/tec/spec/4_4.html
        my %series = (
            'T' => 'Tu-ka',
            '1' => 'cdmaOne',
            '2' => 'CDMA 1X',
            '3' => 'CDMA 1X WIN',
        );
        my $series;
        if (ref $device_map->{$model_long}->{device_id} eq 'ARRAY') {
            $series  = $series{  substr($device_map->{$model_long}->{device_id}->[0], 2, 1) };
        } else {
            $series  = $series{  substr($device_map->{$model_long}->{device_id},      2, 1) };
        }


        # $device_map
        # W32S => {
        #     flash_lite => '1.1',
        #     series     => 'CDMA 1X WIN',
        #     device_id  => [ SN33, SN35 ],
        #     display_wallpaper => { width  => '240', height => '320' },
        #     display_browsing  => { width  => '228', height => '242' },
        # }
        $device_map->{$model_long} = {
            series => $series,
            %{ $device_map->{$model_long} },
            %{ $model },
        };
    }


    my $flash_map;
    for my $model ( values %$device_map ) {
        next unless ($model->{flash_lite});

        # $flash_map
        # SN33 => {
        #    version => '1.1',
        #    width   => '240'
        #    height  => '320',
        #    max_file_size => '200',
        # },
        # SN35 => {
        #     version => '1.1',
        #     width   => '240'
        #     height  => '320',
        #     max_file_size => '200',
        # },
        my @device_id = (ref $model->{device_id} eq 'ARRAY')? @{ $model->{device_id} } : $model->{device_id};
        for my $device_id (@device_id) {
            $flash_map->{$device_id} = {
                version  => $model->{flash_lite},
                width    => $model->{display_wallpaper}->{width}  || $model->{display_browsing}->{width},
                height   => $model->{display_wallpaper}->{height} || $model->{display_browsing}->{width},
                max_file_size => ($model->{series} eq 'CDMA 1X WIN') ? 100 : 48,
                # http://www.au.kddi.com/ezfactory/mm/flash01.html
            };
        }

    }

    return  $flash_map;
}

sub make_map_softbank {

    # - ThirdForce::Service, ThirdForce::UserAgent で取れる model 名が同一
    #    機種で異なる場合がある。(SoftBankのサイトが異なってる)
    #    Service では 913SH, 913SH G が2レコード
    #    UserAgentでは 913SH/913SH G で1レコード
    #
    # - ThirdForce::Service, ThirdForce::UserAgent で取れる model 名が
    #    HTTP::MobileAgent の model と異なる場合が上記以外である。
    #    SoftBankのサイトでは    703SHf
    #    HTTP::MobileAgent では V703SHf
    #
    my $flash_map;
    for my $device (@{WWW::MobileCarrierJP::ThirdForce::Service->scrape()}) {
        if (
            !$device->{flashlite}                  or
            $device->{flashlite} !~ /^\d+(\.\d+)/  or
            $device->{model}     !~ /^[\w\-]+$/
        ) {
            next;
        }

        $flash_map->{$device->{model}} = {
            version  => $device->{flashlite},

            # メディア編のPDF(P170)から
            # http://creation.mb.softbank.jp/doc_tool/web_doc_tool.html
            max_file_size => ($device->{flashlite} eq '1.1') ? 100 : 150,
        };
    }

    for my $device (@{WWW::MobileCarrierJP::ThirdForce::HTTPHeader->scrape()} ) {

        my $model = $device->{model};

        next unless ($flash_map->{$model});

        my ($width, $height) = ($device->{'x-jphone-display'} =~ /^(\d+)\*(\d+)$/);
        $flash_map->{$model}->{width}  = $width;
        $flash_map->{$model}->{height} = $height;
    }

    # Webから取れてくるモデルには V がついてないコトがある対策。
    for my $device (@{WWW::MobileCarrierJP::ThirdForce::UserAgent->scrape()} ) {
        $device->{user_agent} =~ s/^\s+//g;
        $device->{user_agent} =~ s/\s+$//g;
        my $agent = HTTP::MobileAgent->new($device->{user_agent});

        my $model     = $agent->{model};
        my $model_aho = $agent->{model};
           $model_aho =~ s/^.//;
        if ($flash_map->{$model}) {
            ;
        }
        elsif ($flash_map->{$model_aho}) {
            $flash_map->{$model} = $flash_map->{$model_aho};
            delete $flash_map->{$model_aho};
        }
        else {
            next;
        }
    }

    return  $flash_map;
}

# FIXME: ここまでヤルなら TT 使ったほうがよくね?
sub output_pm {
    my $map = shift;

    my $tmpl = $MODULE_TMPL;
    $tmpl =~ s/{{MESSAGE}}/$MESSAGE/;

    if ($SCRAPE_CARRIER eq 'docomo') { 
        $tmpl =~ s/{{MODULE_NAME}}/HTTP::MobileAgent::Flash::DoCoMoFlashMap/g;
        $tmpl =~ s/{{ENV_FLASH_MAP}}/DOCOMO_FLASH_MAP/g;
    }
    elsif ($SCRAPE_CARRIER eq 'ezweb') { 
        $tmpl =~ s/{{MODULE_NAME}}/HTTP::MobileAgent::Flash::EZWebFlashMap/g;
        $tmpl =~ s/{{ENV_FLASH_MAP}}/EZWEB_FLASH_MAP/g;
    }
    elsif ($SCRAPE_CARRIER eq 'softbank') { 
        $tmpl =~ s/{{MODULE_NAME}}/HTTP::MobileAgent::Flash::SoftBankFlashMap/g;
        $tmpl =~ s/{{ENV_FLASH_MAP}}/SOFTBANK_FLASH_MAP/g;
    }

    print $tmpl;
    print "\n";
    print '$FLASH_MAP ||= {' . "\n";

    for my $key (sort keys %$map) {
        print "    '$key' => {\n";
        for my $k (qw(version width height max_file_size)) {
            printf "        %-14s => '%s',\n", $k, $map->{$key}->{$k};
        }
        print "    },\n";
    }

    print "};\n\n1;";
}

sub output_yaml {
    my $map = shift;

    print "$MESSAGE\n";
    print "---\n\n";
    for my $key (sort keys %$map) {
        print "$key:\n";
        for my $k (qw(version width height max_file_size)) {
            printf "  %-14s : %s\n", $k, $map->{$key}->{$k};
        }
    }
}

__END__

=head1 SYNOPSIS

make_map_flash_lite.pl --output=[pm|yaml] --carrier=[docomo|ezweb|softbank]

=cut
1;