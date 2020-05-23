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
our $db;
our @new_files;
our $db_file_count;
our $unix_file_count;

sub s01_init {

    # 1. Initialise environment
    $scr = new vidScreen;

    # 2. Test database access
    $db            = new VidDB();
    $db_file_count = $db->get_new_file_status();

    # 3. Test file-system access
    die "Cannot access $mp4_dir" unless -d $mp4_dir;
    die "Cannot access $pdir"    unless -d $pdir;
    @new_files       = glob( $mp4_dir . '/*.mp4' );
    $unix_file_count = @new_files;
}

sub s021_preprocess {
    my ( $fn, $info, $vhours, $vmins );
    my %val;
    if ( $db_file_count > 1 ) {

        # It looks as if the files have already been added
        $scr->display_status(
            "File processing skipped and using DB - " . $db_file_count . " files to process" );
        return;
    }
    $db->connect();

    # Add any new files to the database
    foreach my $full_name (@new_files) {
        $val{file} = basename $full_name;
        $info      = get_mp4info($full_name);
        $vhours    = int( $info->{MM} / 60 );
        $vmins     = int( $info->{MM} % 60 );
        $val{video_length}
            = sprintf( "%02d:%02d:%02d.%003d", $vhours, $vmins, $info->{SS}, $info->{MS} );

        # Database can't do a version sort, so split the key fields so it can
        if ( $val{file} =~ m/^([^_]*_[^_]*_[^_]*)\./ ) {
            $val{key1} = $1;
            $val{key2} = 0;
        }
        else {
            ( $val{key1}, $val{key2} ) = ( $val{file} =~ /^(.*)_(\d+)\..*$/ );
        }

        # The DB ignores if the file exists already
        $db->add_file(%val);
    }

    # Fetch the number of files again
    my $res = $db->get_new_file_status();
    $scr->display_status(
        sprintf( "Number of new files ready for processing in database = %d", $res ) );
    $db_file_count = $res;
    $db->disconnect();
    return;
}

sub s0221_prepare_file {
    my $short_file  = shift;
    my $target_name = "$mp4_dir/$short_file";
    my $link_name   = "$pdir/$short_file";

    # This is only needed if a previous run failed - it's probably already pointing to
    # the correct file, but re-create it to be certain
    unlink $link_name if -e $link_name;
    system("ln $target_name $link_name") == 0
        or die "Cannot ln $target_name to $link_name";
}

sub s02221_change_section {
    my $curr_values = shift;
    my @times;
    my $ichar;
    my $new_values;
    if ( $curr_values->{program} eq "" ) {
        $scr->display_status("You must define Program first");
        return;
    }
    $curr_values->{section}
        = $scr->get_number( "Section number", $curr_values->{section} + 1 );
    @times
        = $scr->get_start_stop_times(
        ( $curr_values->{start_time}, $curr_values->{video_length} ) );
    return if @times == 0;    # Back was selected
    $curr_values->{start_time} = $times[0];
    $curr_values->{end_time}   = $times[1];
    if ( $db->add_section( 0, $curr_values ) == 1 ) {
        while (1) {
            $ichar = $scr->get_char(
                sprintf "Program %s Series %s Episode %s Section %s already exists - replace?",
                $curr_values->{program}, $curr_values->{series},
                $curr_values->{episode}, $curr_values->{section}
            );
            last if ( $ichar =~ "[yYnN]" );
        }
        return (1) if $ichar =~ "[nN]";
        die "Cannot insert section on 2nd attempt"
            if $db->add_section( 1, $curr_values ) == 1;
    }
    $db->log($curr_values);
    $scr->scroll($curr_values);
    $scr->update_values;
    $scr->display_status("Section created (Total for file=$curr_values->{section_count}");
}

sub s0222_process_file {
    my ( $curr_file, $curr_values, $last_values ) = @_;
    my $c;
    my $extra_option;
    my @file_sections;

    #--
    while (1) {
        $scr->display_values( $curr_values, $curr_file->{section_count} );
        if ( $curr_file->{section_count} == 0 ) {
            $extra_option = "";
        }
        else {
            # Add an extra option
            $extra_option = "," . "e&Xterminate section";
        }
        $c
            = $scr->get_char(
                  "&Quit,&file,&Delete-file,&Program,&Series,&Episode,&section,&Back"
                . $extra_option
                . "?" );
        given ($c) {
            when (/[bB]/) {
                return -1;
            }
            when (/[fF]/) {
                if ( $curr_file->{section_count} == 0 ) {
                    $scr->display_status("No sections defined, so 'F' disabled");
                    next;
                }
                return +1;
            }
            when ('P') {
                my $res = $scr->get_string( "Program name", $curr_values->{program} );
                if ( $res ne $curr_values->{program} ) {
                    $curr_values->{program} = $res;
                    $curr_values->{series}  = 1;
                    $curr_values->{episode} = 1;
                    $curr_values->{section} = 0;
                }
            }
            when ('S') {
                $curr_values->{series}
                    = $scr->get_number( "Series number", $curr_values->{series} + 1 );
                $curr_values->{episode} = 1;
                $curr_values->{section} = 0;
            }
            when ('E') {
                $curr_values->{episode}
                    = $scr->get_number( "Episode number", $curr_values->{episode} + 1 );
                $curr_values->{section} = 0;
            }
            when ('s') { s02221_change_section($curr_values);return -97; }
            when (/[dD]/) {
                my $ichar = $scr->get_yn("Are you sure you want to delete $curr_values->{file}?");
                if ( $ichar eq "y" ) {
                    $db->delete_file( $curr_values->{file} );
                    return -98;
                }
            }
            when (/[xX]/) {
                my $sections = " ";
                my $res      = "-1";
                @file_sections = $db->get_file_sections( $curr_file->{file} );
                for ( my $n = 0; $n < @file_sections; $n++ ) {
                    $sections = $sections . "$file_sections[$n]->{section_id} ";
                }
                if ( @file_sections > 1 ) {
                    while ( index( $sections, " $res " ) == -1 and $res != 0 ) {
                        $res = $scr->get_number("Which section_id shall I delete? ($sections)");
                        printf "$res\n";
                    }
                    next if $res == 0;
                }
                else {
                    $res = $file_sections[0]->{section_id};
                }
                my $ichar = $scr->get_yn("Are you sure you want to delete section_id $res?");
                next if ( $ichar eq "n" );
                $db->delete_section($res);
                return -97;
            }
            when (/[qQ]/) { return -99; }
        }
    }
    exit();
}

sub s0223_tidy_file {
    my $short_file = shift;
    my $link_name  = "$pdir/$short_file";
    unlink $link_name if -e $link_name;
}

sub s0224_delete_file {
    my $short_file = shift;
    my $fn         = "$mp4_dir/$short_file";
    rename $fn, $fn . ".remove" or die "Failed to 'delete' $fn";
}

sub s022_process_new_files {

    my ($new_file_status) = @_;
    my $file_sub = 0;
    my $curr_file;
    my $result;
    my @file_sections;
    my $skip_over_files_with_sections = 1;

    # Get the new files to process from the DB
    my $all_files = $db->fetch_new_files();

    # Get the details of the last section we processed as the starting values
    my $last_values = $db->get_last_values();
    my $curr_values = clone $last_values;
    $scr->display_screen();
    while ( $file_sub < @{$all_files} ) {
        $curr_file = @{$all_files}[$file_sub];

        # If a file we've already processed, then scroll it on the window and go on to the next
        # UNLESS $skip_over_files_with_sections is 0 .............
        if ( $curr_file->{section_count} > 0 ) {
            @file_sections = $db->get_file_sections( $curr_file->{file} );
            for ( my $n = 0; $n < @file_sections; $n++ ) {
                $scr->scroll( $file_sections[$n] );
            }
            if ( $skip_over_files_with_sections == 1 ) {
                $file_sub++;
                next;
            }
        }
        $skip_over_files_with_sections = 0;
        $curr_values->{file}           = $curr_file->{file};
        $curr_values->{start_time}     = "00:00:00.000";
        $curr_values->{end_time}       = $curr_file->{video_length};
        $curr_values->{video_length}   = $curr_file->{video_length};

        #--
        if (   $curr_file->{section_count} < 1
            or $skip_over_files_with_sections == 0 )
        {
            $skip_over_files_with_sections = 0;   # We need this in case we need to step back a file
            s0221_prepare_file( $curr_file->{file} );
            $result = s0222_process_file( $curr_file, $curr_values, $last_values );
            s0223_tidy_file( $curr_file->{file} );
            given ($result) {
                when (-97) {

                    # We've deleted a section -re-read what we have
                    $all_files = $db->fetch_new_files();
                    next;
                }
                when (-98) {
                    s0224_delete_file( $curr_file->{file} );
                    splice( @{$all_files}, $file_sub, 1 );
                    next;
                }
                when (-99) { last; }    # quit
            }    # Skip over files with sections
        }
        else {
            $scr->display_status( $curr_values->{file} . " has "
                    . $curr_file->{section_count}
                    . " section - skipping" );
            sleep(0.25);
            $last_values = clone $curr_values;
            $scr->display_values( $curr_values, $curr_file->{section_count} );
        }
        $file_sub += $result;
    }
}

#    while ($file_sub < $new_file_status->db_total_count)
sub s02_process {
    s021_preprocess();
    s022_process_new_files;
}

sub main {
    s01_init();
    #
    s02_process();
    print "yup";
}
main();
