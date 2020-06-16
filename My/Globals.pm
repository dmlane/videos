#!/usr/bin/env perl
use strict;

package My::Globals;
use Carp;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
use parent 'Exporter';

#use Carp;
our $VERSION = 1.0;
our @ISA     = qw(Exporter);

# --
@EXPORT    = qw($db $scr $mp4_dir $os $pdir );
@EXPORT_OK = qw();
our $db;
our %mp4_base_dir_options = (
    darwin  => "/System/Volumes/Data",
    linux   => "/Diskstation",
    MSWin32 => "Z:\\Videos\\Import"
);
my $os = $^O;
croak "Unknown environment $os" unless ( defined $mp4_base_dir_options{$os} );
our $mp4_dir = $mp4_base_dir_options{$os} . "/Unix/Videos/Import";
our $pdir    = $mp4_base_dir_options{$os} . "/Unix/Videos/Import/processing";
our $scr;
1;
