#!/usr/bin/perl -w
use strict;
use MP4::Info;
use Term::ReadKey;
use Switch;

my ($fn) = @ARGV;

my $info   = get_mp4info($fn);
my $vhours = int( $info->{MM} / 60 );
my $vmins  = int( $info->{MM} % 60 );
printf( "%02d:%02d:%02d.%003d\n", $vhours, $vmins, $info->{SS}, $info->{MS} );

