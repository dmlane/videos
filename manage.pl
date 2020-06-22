#!/usr/bin/env perl
use strict;
use File::Basename;
use Term::ReadKey;
use Term::ANSIColor qw(colored);
use Term::Cap;
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

#use Term::Menus;
my $terminal;
eval { $terminal = Term::Cap->Tgetent(); };
my $clear = $terminal->Tputs('cl');
my @data;
my @episode_count;
my @error = (
    "OK",
    "Repeated section",
    "Missing section",
    "Suspicious file name",
    "Missed file?", "Start time precedes prev end time",
    "end_time<=start_time"
);
$error[99] = "Outlier";

sub s01_init {
    $db = new VidDB();
}

sub s020_set_episode_count {
    my $ptr;
    @episode_count = @{ $db->get_episode_counts() };
    for ( my $n = 0; $n < @episode_count; $n++ ) {
        $ptr = \%{ $episode_count[$n] };
        next if ( defined $ptr->{max_episodes} );
        while (1) {
            printf( "How many episodes in %s series %s? ",
                $ptr->{program_name}, $ptr->{series_number} );
            printf("                     -1 for films");
            my $episodes = <> + 0;
            printf( "\nConfirm '%s' episodes?", $episodes );
            if ( get_yn() eq 'y' ) {
                printf("\nProcessing\n");
                $db->set_max_episodes( $ptr->{program_name}, $ptr->{series_number}, $episodes );
                last;
            }
        }
 
    }
}

sub s0211_compare_values {
    my ( $last_rec, $curr_rec ) = @_;
    my $prog     = $curr_rec->{program_name};
    my $duration = $curr_rec->{end_time} - $curr_rec->{start_time};
    if (   $last_rec->{program_name} ne $curr_rec->{program_name}
        or $last_rec->{series_number} != $curr_rec->{series_number}
        or $last_rec->{episode_number} != $curr_rec->{episode_number} )
    {
        return 0;
    }

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

sub s022_check_order {

    my $res;
    my $errs = 0;
    my $msg;
    my $osub     = 0;
    my $last_rec = \%{ $data[0] };
    my $curr_rec;

    for ( my $n = 1; $n < @data; $n++ ) {
        $curr_rec = \%{ $data[$n] };
        $curr_rec->{status} = s0211_compare_values( $last_rec, $curr_rec );
        $last_rec = \%{ $data[$n] };
        if ( $curr_rec->{status} != 0 ) {
            printf("$curr_rec->{status} ....\n");
        }
    }
    return $errs;
}

sub s021_mark_last_records {
    my $ptr;
    my $prev     = \%{ $data[0] };
    my $duration = 0.000;
    for ( my $n = 0; $n < @data; $n++ ) {
        $ptr = \%{ $data[$n] };
        $ptr->{end_flag} = 0;
        unless ($ptr->{program_name} eq $prev->{program_name}
            and $ptr->{series_number} == $prev->{series_number}
            and $ptr->{episode_number} == $prev->{episode_number} )
        {
            $data[ $n - 1 ]->{end_flag} += 1;
        }
        unless ($ptr->{k1} eq $prev->{k1}
            and $ptr->{k2} == $prev->{k2} )
        {
            $prev->{end_flag} += 2;
        }
        $prev = \%{ $data[$n] };
    }
    $prev->{end_flag} = 3;
    for ( my $n = 0; $n < @data; $n++ ) {
        $ptr = \%{ $data[$n] };
        $duration += $ptr->{end_time} - $ptr->{start_time};
        $ptr->{duration} = $duration;
        $duration = 0.000 if $ptr->{end_flag} % 2 == 1;
    }
}

sub s023_mark_outliers {
    my $ptr;
    my @outliers = @{ $db->get_outliers() };
    my $o        = 0;
    my $optr     = \%{ $outliers[$0] };
    for ( my $n = 0; $n < @data && $o < @outliers; $n++ ) {
        $ptr = \%{ $data[$n] };
        next if $ptr->{end_flag} % 2 == 0;
        if (    $ptr->{program_name} eq $outliers[$o]->{program_name}
            and $ptr->{series_number} == $outliers[$o]->{series_number}
            and $ptr->{episode_number} == $outliers[$o]->{episode_number} )
        {
            $ptr->{status} = 99 if $ptr->{status} == 0;
            $o++;
            $optr = \%{ $outliers[$o] };
        }
    }
}

sub get_yn {
    my $c = 'x';
    ReadMode('cbreak');
    until ( $c =~ "[yYnN]" ) {
        $c = ReadKey(0);
    }
    ReadMode('normal');
    return lc($c);
}

sub s024_process {

    my $ptr;
    my $last_ptr;
    my $start_sub = 0;
    my $end_sub;
    my $err_count = 0;
    my $msg;
    my $underline = "";

    $last_ptr = \%{ $data[0] };
    for ( my $n = 0; $n < @data; $n++ ) {
        $ptr = \%{ $data[$n] };
        if (    $ptr->{program_name} eq $last_ptr->{program_name}
            and $ptr->{series_number} == $last_ptr->{series_number} )
        {
            $err_count++ if $ptr->{status} != 0;
            $last_ptr = \%{ $data[$n] };
            $end_sub  = $n;
            next;
        }
        if ( $err_count == 0 ) {
            print $clear;
            printf(
                "\n%s series %s : has no problems - mark for processing?",
                $last_ptr->{program_name},
                $last_ptr->{series_number}
            );
            if ( get_yn() eq 'y' ) {
                printf("\nProcessing\n");
                $db->accept_series( $last_ptr->{program_name}, $last_ptr->{series_number} );
            }
            $start_sub = $n;
            $last_ptr  = \%{ $data[$n] };
            next;
        }
        print $clear;
        for ( my $m = $start_sub; $m <= $end_sub; $m++ ) {
            $ptr = \%{ $data[$m] };
            if ( $ptr->{end_flag} % 2 == 1 ) {
                $underline = " underline";
            }
            else {
                $underline = "";
            }
            $msg = sprintf(
                "%7d: %-30s %2d %2d %2d %19s %2d %s %s %s",
                $ptr->{section_id},          $ptr->{program_name},
                $ptr->{series_number},       $ptr->{episode_number},
                $ptr->{section_number},      $ptr->{k1},
                $ptr->{k2},                  to_time( $ptr->{start_time} ),
                to_time( $ptr->{end_time} ), to_time( $ptr->{duration} )
            );
            given ( $ptr->{status} ) {
                when (0) {
                    printf( "%s\n", colored( $msg, "green$underline" ) );
                }
                when (99) {
                    printf( "%s\n",
                              colored( $msg, "yellow$underline" ) . " "
                            . colored( $error[ $ptr->{status} ], "red" ) );
                }
                default {
                    printf( "%s\n",
                              colored( $msg, "yellow$underline" ) . " "
                            . colored( $error[ $ptr->{status} ], "red" ) );
                }
            }
        }
        printf(
            "%s series %s : has a problem - fix?",
            $last_ptr->{program_name},
            $last_ptr->{series_number}
        );
        if ( get_yn() eq 'y' ) {

            # Mark it
        }
        $err_count = 0;
        $start_sub = $n;
        $last_ptr  = \%{ $data[$n] };
    }
}

sub s02_process {
    my $res;
    @data = @{ $db->get_ordered_sections() };
    s020_set_episode_count();
    s021_mark_last_records();
    s022_check_order();
    s023_mark_outliers();
    s024_process();
}
s01_init();
s02_process();
