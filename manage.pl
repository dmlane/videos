#!/usr/bin/env perl
use strict;
use File::Basename;
use Term::ANSIColor qw(colored);
use MP4::Info;
use Const::Fast;
use lib dirname(__FILE__);
use VidDB 'PROD';

#use VidDB 'TEST';
use vidScreen;
use My::Globals;
use Time::HiRes qw (sleep);
use feature 'switch';
no warnings 'experimental::smartmatch';

use Term::Menus;

my $db;
my %prog;
my $sections;
my %summary;
my @outliers;
my $total_duration;
my $new_episode = 0;

sub s01_init {
    $db = new VidDB();
}

sub s0211_compare_values {
    my ( $last_rec, $curr_rec ) = @_;
    my $prog     = $curr_rec->{program_name};
    my $duration = $curr_rec->{end_time} - $curr_rec->{start_time};
    if (   $last_rec->{program_name} ne $curr_rec->{program_name}
        or $last_rec->{series_number} != $curr_rec->{series_number}
        or $last_rec->{episode_number} != $curr_rec->{episode_number} )
    {
        $total_duration = $duration;
        $new_episode    = 1;
        return 0;
    }
    $new_episode = 0;
    $total_duration += $duration;

    # Repeat section
    return 1 if $last_rec->{section_number} == $curr_rec->{section_number};

    # Missing section;
    return 2 if ( $last_rec->{section_number} + 1 ) != $curr_rec->{section_number};

    # Suspicious file name?
    return 3 if ( $last_rec->{k1} gt $curr_rec->{k1} );
    return 3 if ( $last_rec->{k1} eq $curr_rec->{k1} and $last_rec->{k2} > $curr_rec->{k2} );

    # If skipped to next file, then should be OK
    return 0
        if ( $last_rec->{k1} eq $curr_rec->{k1} and ( $last_rec->{k2} + 1 ) == $curr_rec->{k2} );

    # Missed file?
    return 4 if ( $last_rec->{k1} ne $curr_rec->{k1} or $last_rec->{k2} != $curr_rec->{k2} );

    # Start-time precedes last end_time time?
    return 5 if ( $last_rec->{end_time} > $curr_rec->{start_time} );

    # Problem with record?
    return 6 if ( $curr_rec->{start_time} >= $curr_rec->{end_time} );
}

sub to_time {
    my $tsecs = shift;
    my $tmin  = int( $tsecs / 60 );
    $tsecs = $tsecs - ( $tmin * 60 );
    return
        sprintf( "%2.2d:%2.2d.%3.3d", $tmin, int($tsecs), int( ( $tsecs - int($tsecs) ) * 1000 ) );
}

sub s021_check_order {

    # program_name,series_number,episode_number,section_number,start_time,end_time,
    # time_to_sec(end_time)-time_to_sec(start_time) duration
    my $res;
    my $errs = 0;
    my $msg;
    my $osub  = 0;
    my @error = (
        "OK",
        "Repeated section",
        "Missing section",
        "Suspicious file name",
        "Missed file?", "Start time precedes prev end time",
        "end_time<=start_time"
    );

   # @outliers = @{ $db->get_outliers() };
    my %last_rec = (
        program_name   => " ",
        series_number  => -1,
        episode_number => -1,
        section_number => -1,
        start_time     => 0.000,
        end_time       => 0.000,
        k1             => "",
        k2             => ""
    );
    my @data = @{$sections};
    my $curr_rec;
    #my $outlier = 0;

    for ( my $n = 0; $n < @data; $n++ ) {
        # if ( $new_episode == 1 and $outlier == 1 ) {
        #     printf( " [%s]", colored( "<< Outlier>>", "red" ) );
        #     $outlier = 0;
        #     print "\nPress ENTER to continue:";
        #     <STDIN>;
        # }
        $curr_rec = $data[$n];
        $res      = s0211_compare_values( \%last_rec, $curr_rec );
        $msg      = sprintf(
            "%7d: %-30s %2d %2d %2d %19s %2d %s %s %s",
            $data[$n]->{section_id},          $data[$n]->{program_name},
            $data[$n]->{series_number},       $data[$n]->{episode_number},
            $data[$n]->{section_number},      $data[$n]->{k1},
            $data[$n]->{k2},                  to_time( $data[$n]->{start_time} ),
            to_time( $data[$n]->{end_time} ), to_time($total_duration)
        );
        if ( $res == 0 ) {
            # if (    $outliers[$osub]->{program_name} eq $data[$n]->{program_name}
            #     and $outliers[$osub]->{series_number} == $data[$n]->{series_number}
            #     and $outliers[$osub]->{episode_number} == $data[$n]->{episode_number} )
            # {
            #     $outlier = 1;
            # }
            printf( "%s\n", colored( $msg, "green" ) );
        }
        else {
            $errs++;
            printf( "%s [%s]\n", colored( $msg, "yellow" ), colored( $error[$res], "red" ) );
            printf "Press ENTER to continue:";
            <STDIN>;
        }
        $last_rec{program_name}   = $data[$n]->{program_name};
        $last_rec{series_number}  = $data[$n]->{series_number};
        $last_rec{episode_number} = $data[$n]->{episode_number};
        $last_rec{section_number} = $data[$n]->{section_number};
        $last_rec{start_time}     = $data[$n]->{start_time};
        $last_rec{end_time}       = $data[$n]->{end_time};
        $last_rec{k1}             = $data[$n]->{k1};
        $last_rec{k2}             = $data[$n]->{k2};
    }
     return $errs;
}

sub s021_series_count {
}

sub s02_process {
    my $res;

    #   my @menu=(
    # "Show programs with missing Total-Episodes",
    # "Quit"
    #       );
    #   s021_series_count();
    $sections = $db->get_ordered_sections();
    $res      = s021_check_order();
}
s01_init();
s02_process();
