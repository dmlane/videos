#!/usr/bin/env perl
use strict;
use File::Basename;
use File::Copy qw(copy);
use MP4::Info;
use Const::Fast;
use lib dirname(__FILE__);
use VidDB;
use vidScreen;
use feature 'switch';

no warnings 'experimental::smartmatch';
const our $logfile => $ENV{"HOME"} . "/data/videos.log";
our $db;
my $screen;
my %global = (

    # Database connection
    login_path => "videos",
    database   => "videos",

    # Comment these 2 lines out to switch to production
    login_path => "testdb",
    database   => "test",

    # Enable logging
    db_debug => 1,

    # Where we find the new videos
    mp4_base_dir_options => {
        mac     => "/System/Volumes/Data",
        linux   => "/Diskstation",
        MSWin32 => "Z:\\Videos\\Import"
    },
    mp4_dir     => "",
    data_subdir => "/Unix/Videos/Import",
    pdir        => "/processing",
);

sub s01_init {
    my ( $dir, $pdir );

    # 1. Initialise environment
    $dir = $global{mp4_base_dir_options}{$^O};
    die "OS '$^O' not expected" unless length $dir;
    $dir             = $dir . $global{data_subdir};
    $pdir            = $dir . $global{pdir};
    $global{mp4_dir} = $dir;
    $global{pdir}    = $pdir;
    $screen          = new vidScreen;

    # 2. Test database access
    $db = new VidDB(
        {   database   => $global{database},
            login_path => $global{login_path},
            debug      => $global{db_debug}
        }
    );
    my $res = $db->get_new_file_status();

    # 3. Test file-system access
    die "Cannot access $dir"  unless -d $dir;
    die "Cannot access $pdir" unless -d $pdir;
    $global{new_files} = [ glob( $dir . '/*.mp4' ) ];
    $res->{mp4_files} = @{ $global{new_files} };
    my $modtime = ( stat($logfile) )[9];

    # Create a safety copy
    my $logfile_copy = $logfile . "." . $modtime;
    if ( -e $logfile ) {
        copy $logfile, $logfile_copy or die "Cannot make backup copy of log";
        utime( undef, $modtime, $logfile_copy );
    }
    open( LOG, '>>', $logfile ) or die "Cannot open log file $logfile";
    return ($res);
}

sub s021_preprocess {
    my ($new_file_status) = @_;
    my ( $fn, $full_name, $info, $vhours, $vmins );
    my %val;
    if ( $new_file_status->{db_total_count} >= $new_file_status->{mp4_files} )
    {
        # It looks as if the files have already been added
        $screen->display_status( "File processing skipped and using DB - "
                . $new_file_status->{db_total_count}
                . " files to process" );
        return $new_file_status;
    }
    $db->connect();

    # Add any new files to the database
    foreach $full_name ( @{ $global{new_files} } ) {
        $val{file}         = basename $full_name;
        $info              = get_mp4info($full_name);
        $vhours            = int( $info->{MM} / 60 );
        $vmins             = int( $info->{MM} % 60 );
        $val{video_length} = sprintf( "%02d:%02d:%02d.%003d",
            $vhours, $vmins, $info->{SS}, $info->{MS} );

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
    $screen->display_status(
        sprintf(
            "Number of new files added to database = %d (now %d in total)",
            $res->{db_total_count} - $new_file_status->{db_total_count},
            $res->{db_total_count}
        )
    );
    $new_file_status->{db_total_count} = $res->{db_total_count};
    $db->disconnect();
    return $new_file_status;
}

sub s0221_prepare_file {
    my $short_file  = shift;
    my $target_name = "$global{mp4_dir}/$short_file";
    my $link_name   = "$global{pdir}/$short_file";

# This is only needed if a previous run failed - it's probably already pointing to
# the correct file, but re-create it to be certain
    unlink $link_name if -e $link_name;
    system("ln $target_name $link_name") == 0
        or die "Cannot ln $target_name to $link_name";
}

sub s0222_process_file {
    my ( $curr_file, $curr_values, $last_values ) = @_;
    my $c;

    sub delete_file {
        my $ichar;
        while (1) {
            $ichar
                = $screen->get_char(
                "Are you sure you want to delete $curr_file?");
            last INNER if $ichar =~ "[yYnN]";
        }
        $db->delete_file($curr_file);
    }

    sub change_program {
        my $res
            = $screen->get_string( "Program name", $curr_values->{program} );
        if ( $res ne $curr_values->{program} ) {
            $curr_values->{program} = $res;
            $curr_values->{series}  = 1;
            $curr_values->{episode} = 1;
            $curr_values->{section} = 0;
        }
    }

    sub change_series {
        $curr_values->{series} = $screen->get_number( "Series number",
            $curr_values->{series} + 1 );
        $curr_values->{episode} = 1;
        $curr_values->{section} = 0;
    }

    sub change_episode {
        $curr_values->{episode} = $screen->get_number( "Episode number",
            $curr_values->{episode} + 1 );
        $curr_values->{section} = 0;
    }

    sub change_section {
        my @times;
        my $ichar;
        if ( $curr_values->{program} eq "" ) {
            $screen->display_status("You must define Program first");
            return;
        }
        $curr_values->{series} = $screen->get_number( "Section number",
            $curr_values->{section} + 1 );
        @times
            = $screen->get_start_stop_times(
            ( $curr_values->{start_time}, $curr_values->{end_time} ) );
        return if @times == 0;    # Back was selected
        $curr_values->{start_time} = $times[0];
        $curr_values->{end_time}   = $times[1];
        sleep 5;
        if ( $db->add_section( 0, $curr_values ) == 1 ) {
            while (1) {
                $ichar = $screen->get_char(
                    sprintf
                        "Program %s Series %s Episode %s Section %s already exists - replace?",
                    $curr_values->{program}, $curr_values->{series},
                    $curr_values->{episode}, $curr_values->{section}
                );
                last if ( $ichar =~ "[yYnN]" );
            }
            return (1) if $ichar =~ "[nN]";
            die "Cannot insert section on 2nd attempt"
                if $db->add_section( 0, $curr_values ) == 1;
        }
        printf LOG "%s,%s,%s,%s,%2.2d,%2.2d,%2.2d\n", $curr_values->{file},
            $curr_values->{start_time}, $curr_values->{end_time},
            $curr_values->{program},
            $curr_values->{series}, $curr_values->{episode},
            $curr_values->{section};
        $screen->scroll(
            sprintf(
                "%s %s -> %s %s_S%2.2dE%2.2d-%2.2d",
                $curr_values->{start_time}, $curr_values->{end_time},
                $curr_values->{program},    $curr_values->{series},
                $curr_values->{episode},    $curr_values->{section}
            )
        );
        $screen->update_values;
        $screen->display_status(
            "Section created (Total for file=$curr_values->{section_count}");
    }

    #--
    while (1) {
        $screen->display_values($curr_values);
        $c = $screen->get_char("file,Program,Series,Episode,section,Back?");
        given ($c) {
            when (/[bB]/) { return -1; }
            when ('f')    { return +1; }
            when ('F')    { return -97; }
            when ('S')    { change_series(); }
            when ('E')    { change_episode(); }
            when ('s')    { change_section(); }
            when ('P')    { change_program(); }
            when (/[dD]/) { delete_file(); return -98; }
            when (/[qQ]/) { return -99; }
        }
    }
    sleep(5);
    exit();
}

sub s0223_tidy_file {
    my $short_file = shift;
    my $link_name  = "$global{pdir}/$short_file";
    unlink $link_name if -e $link_name;
}

sub s0224_delete_file {
    my $short_file = shift;
    my $fn         = "$global{dir}/$short_file";
    rename $fn, $fn . ".remove" or die "Failed to 'delete' $fn";
}

sub s022_process_new_files {

    my ($new_file_status) = @_;
    my $file_sub = 0;
    my $curr_file;
    my $result;
    my $skip_over_files_with_sections = 0;

    # Get the new files to process from the DB
    my $all_files = $db->fetch_new_files();

    # Get the details of the last section we processed as the starting values
    my $last_values = $db->get_last_values();
    my $curr_values = clone $last_values;
    $screen->display_screen();
    while ( $file_sub < @{$all_files} ) {
        $curr_file                 = @{$all_files}[$file_sub];
        $curr_values->{file}       = @{$all_files}[$file_sub]->{file};
        $curr_values->{start_time} = "00:00:00.000";
        $curr_values->{end_time}   = $curr_file->{video_length};
        if (   $curr_values->{section_count} < 0
            or $skip_over_files_with_sections == 0 )
        {
            s0221_prepare_file( $curr_file->{file} );
            $result
                = s0222_process_file( $curr_file, $curr_values,
                $last_values );
            s0223_tidy_file( $curr_file->{file} );
            given ($result) {
                when (-97) {
                    $skip_over_files_with_sections = 1;
                    $result                        = 1;
                }
                when (-98) {
                    s0224_delete_file( $curr_file->{file} );
                    splice( @{$all_files}, $file_sub, 1 );
                    next;
                }
                when (-99) { last; }    # quit
            }    # Skip over files with sections
        }
    }
    $file_sub += $result;
}

#    while ($file_sub < $new_file_status->db_total_count)
sub s02_process {
    my ($new_file_status) = @_;
    $new_file_status = s021_preprocess($new_file_status);
    s022_process_new_files($new_file_status);
    close(LOG);
}

sub main {
    my $new_file_status = s01_init();
    #
    s02_process($new_file_status);
    print "yup";
}
main();
