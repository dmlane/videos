#!/usr/bin/env perl -w
use strict;
use Pod::Usage;
use DBI;
use MP4::Info;
use Getopt::Std;
use File::Basename;
use feature 'switch';
use Clipboard;
use Const::Fast;
use Carp qw( croak );
use lib dirname(__FILE__);
use VidScreen;

#use VidKomodo;
use VidDB;
no warnings 'experimental::smartmatch';

#=========================================================================#
const my $ReserveLines => 4;
const my $HistorySize  => 20;
const our $ctrlC_value => "#ControlC#";
const our $logfile     => $ENV{"HOME"} . "/data/videos.log";

# Defines where we pick up the new videos (may be overridden by command line option)
my $dir = "/System/Volumes/Data";
$dir = "/Diskstation" if $^O eq "linux";
$dir = $dir . "/Unix/Videos/Import";
my $pdir = $dir . "/processing";
$dir = "Z:\\Videos\\Import" if $^O eq "MSWin32";
my $procfile = "#";

#my $screen   = new VidKomodo;
my $screen = new VidScreen;
my $db     = new VidDB( "videos", "videos" );
open( LOG, '>>', $logfile ) or die "Cannot open log file $logfile";
our $new_files;     # Array of all new files to process
our $last_state;    # Details from last run
our $skip_files_with_sections = 0;   # Set to 1 if we want to skip over files where num_sections !=0

sub fill_buff {

    # **
    my $last20       = $db->get_last20_sections();
    my $last_element = $#{$last20};
    my $element;
    if ( $last_element < 0 ) {
        $element
            = { program_name => "", series_number => 1, episode_number => 1, section_number => 0 };
        return $element;
    }
    for ( my $n = 0; $n <= $last_element; $n++ ) {
        $element = scalar @{$last20}[$n];
        $screen->scroll_top(
            sprintf(
                "%s %s -> %s %s_S%2.2dE%2.2d-%2.2d",
                $element->{file_name},     $element->{start_time},
                $element->{end_time},      $element->{program_name},
                $element->{series_number}, $element->{episode_number},
                $element->{section_number}
            )
        );
    }
    return @{$last20}[$last_element];
}

=head2 save_results
Put new entry in database *or* replace existing entry
=cut

sub save_results {

    my ( $current, $start_time, $end_time, $file_sub ) = @_;
    my $exists = 0;
    my $ichar;
    my $prompt;
    my $change_in_sections = 1;

    if ( $db->db_add_section( $current, $start_time, $end_time, 0 ) == 1 ) {
        while (1) {
            $prompt
                = sprintf "Program %s Series %s Episode %s Section %s already exists - replace?",
                $current->{program},
                $current->{series}, $current->{episode}, $current->{section};
            $ichar = $screen->get_char("$prompt");
            last if ( $ichar =~ "[yYnN]" );
        }
        if ( $ichar =~ "[nN]" ) {
            return (1);
        }
        die "Cannot insert section on 2nd attempt"
            if $db->db_add_section( $current, $start_time, $end_time, 1 ) == 1;
        $change_in_sections = 0;
    }
    printf LOG "%s,%s,%s,%s,%2.2d,%2.2d,%2.2d\n", $current->{file}, $start_time, $end_time,
        $current->{program},
        $current->{series}, $current->{episode}, $current->{section};
    @{$new_files}[$file_sub]->{section_count} += $change_in_sections;
    $screen->scroll_top(
        sprintf(
            "%s %s -> %s %s_S%2.2dE%2.2d-%2.2d",
            $current->{file},   $start_time,         $end_time, $current->{program},
            $current->{series}, $current->{episode}, $current->{section}
        )
    );
    $screen->update_values();
    return 0;
}

=head2 fetch_new_files
Insert details of any new files found in $dir into the table new_files. We remove any files
already present in raw_file (as it means they have already been partially or fully processed)
=cut

sub fetch_new_files {
    my ( $stmt, $fn, $info, $vhours, $vmins, $video_length, $epoch_timestamp, $sfn, $rv,
        $result, $k1, $k2 );
    $screen->print_status("Looking for new files to process");

    #Get a list of all files in $dir which haven't already been processed
    $db->db_connect();
    for $fn (<$dir/V*.mp4>) {
        $info   = get_mp4info($fn);
        $vhours = int( $info->{MM} / 60 );
        $vmins  = int( $info->{MM} % 60 );
        $video_length
            = sprintf( "%02d:%02d:%02d.%003d", $vhours, $vmins, $info->{SS}, $info->{MS} );
        $epoch_timestamp = ( stat($fn) )[9];
        $sfn             = basename($fn);
        if ( $sfn =~ m/^([^_]*_[^_]*_[^_]*)\./ ) {
            $k1 = $1;
            $k2 = 0;
        }
        else {
            ( $k1, $k2 ) = ( $sfn =~ /^(.*)_(\d+)\..*$/ );
        }
        $db->db_add_new_file( $sfn, $k1, $k2, $video_length, $epoch_timestamp );
    }
    $db->db_close();

    # Get records into an array
    #$result = $db->db_fetch_new_files();
    $new_files = $db->db_fetch_new_files();
    $screen->print_status( sprintf "There are now %d new files to process", scalar @{$new_files} );
    return $result;
}

sub get_program {
    my ($default) = @_;
    my $value;

    #printf STDERR "What is the program name [$default]";
    $value = $screen->get_string( "What is the program name", $default );

    #$value = <STDIN>;
    chomp $value;
    $screen->print_status("Program changed from $default to $value");
    return $default if ( length($value) < 1 );
    return ($value);
}

=head2 process_file
=cut

sub process_file {

    # **
    #our ( $previous, $current, $video_length ) = @_;
    our ( $previous, $current, $file_sub ) = @_;
    my $video_length = @{$new_files}[$file_sub]->{video_length};
    my $prompt       = "";
    my $char;
    my $ichar;
    our $HI = chr(27) . '[1;33m';
    our $MD = chr(27) . '[1;36m';
    our $LO = chr(27) . '[0m';
    my ( $start_time, $end_time ) = [ ('00:00:00.000') x 2 ];
    our $result;
    my ( $start_new, $end_new ) = [ ('00:00:00.000') x 2 ];
    our %delta;
    my @nm = ( "file", "Program", "Series", "Episode", "Section" );
    my $fn = $dir . "/" . $current->{file};

    $procfile = $pdir . "/" . $current->{file};
    system("ln $fn $procfile") == 0 or die "Cannot ln $fn to $procfile";

    sub format_changes {
        %delta = %{$current};
        foreach my $key ( keys %{$current} ) {
            if ( $current->{$key} eq $previous->{$key} ) {
                $delta{$key} = $MD . $delta{$key} . $LO;
            }
            else {
                $delta{$key} = $HI . $delta{$key} . $LO;
                $previous->{$key} = $current->{$key};
            }
        }
        $result
            = sprintf "File %s Prog %s Ser %s Epis %s Sect %s (#%d):",
            $delta{file},
            $delta{program},
            $delta{series}, $delta{episode}, $delta{section},
            @{$new_files}[$file_sub]->{section_count};
        return $result;
    }
OUTER: while (1) {
        $screen->show_values(
            $current->{file},    $current->{program}, $current->{series}, $current->{episode},
            $current->{section}, $start_time,         $end_time
        );
        $char = $screen->get_char( format_changes() );
        my $saved;
        given ($char) {
            when (/[bB]/) { last OUTER; }
            when ('P') {
                $current->{program} = get_program( $current->{program} );
            }
            when ('S') {
                $saved = $current->{series};
                $current->{series} = $screen->get_string( "Series", $saved + 1 );
                $screen->print_status("Series changed from $saved to $current->{series} ");
            }
            when ('E') {
                $saved = $current->{episode};
                $current->{episode} = $screen->get_string( "Episode", $saved + 1 );
                $screen->print_status("Series changed from $saved to $current->{episode} ");
                $current->{section} = 0;
            }
            when ('f') { last OUTER; }
            when ('F') {
                $skip_files_with_sections = 1;
                last OUTER;
            }
            when (/[dD]/) {
            INNER: while (1) {
                    $ichar = $ichar = $screen->get_char("Are you sure you want to delete $fn?");
                    last INNER if $ichar =~ "[yYnN]";
                }
                if ( $ichar =~ "[Yy]" ) {
                    $db->db_execute(
                        qq(update raw_file set status=99 where name="$current->{file}"));
                    rename $fn, $fn . ".remove";
                    last OUTER;
                }
            }
            when ('s') {
                if ( $current->{program} eq "" ) {
                    $screen->print_status("You must define Program first");
                    next OUTER;
                }
                $current->{section} = $screen->get_number( "section", $current->{section} + 1 );
                $start_time         = "00:00:00.000";
                $end_time           = $video_length;
            INNER: while (1) {
                    $start_new = $screen->get_timestamp( "Start time", $start_time );
                    $screen->show_values(
                        $current->{file},    $current->{program}, $current->{series},
                        $current->{episode}, $current->{section}, $start_time,
                        $end_time
                    );
                    $end_new = $screen->get_timestamp( "End time", $end_time );
                    $screen->show_values(
                        $current->{file},    $current->{program}, $current->{series},
                        $current->{episode}, $current->{section}, $start_time,
                        $end_time
                    );
                    $ichar = $screen->get_char("$start_new -> $end_new     Y=OK (B=Back)?");
                    last INNER if $ichar =~ "[yYbB]";
                }
                if ( $ichar =~ "[yY]" ) {
                    if ( save_results( $current, $start_new, $end_new, $file_sub ) == 0 ) {
                        $start_time = $start_new;
                        $end_time   = $end_new;
                        $screen->print_status(
                            "Section created (Total for file=$current->section_count");
                    }
                    else {
                        $screen->print_status("Section not created!");
                    }
                }
            }
            when (/[qQ]/) {
                unlink $procfile or die "Cannot rm $procfile";
                $procfile = "#;";
                exit(0);
            }
        }
    }
    unlink $procfile or die "Cannot rm $procfile";
    $procfile = "#";
    return 1 if ( $char =~ "[bB]" );    # Go back to previous file
    return 0;
}

=head2 process_new_files
=cut

sub process_new_files {

    # **
    my %previous_value = ( file => "", program => "", series => 1, episode => 1, section => 0 );
    my %current_value  = ( file => "", program => "", series => 1, episode => 1, section => 0 );
    my $prompt;
    my $file_sub;
    my $file;

    $current_value{program} = $last_state->{program_name};
    $current_value{series}  = $last_state->{series_number};
    $current_value{episode} = $last_state->{episode_number};
    $current_value{section} = $last_state->{section_number};
    $file_sub               = 0;
    while ( $file_sub < @{$new_files} ) {
        $file = @{$new_files}[$file_sub];
        unless ( $file->{section_count} == 0 or $skip_files_with_sections == 0 ) {
            $file_sub++;
            next;
        }
        $current_value{file} = $file->{name};

        #if ( process_file( \%previous_value, \%current_value, $file->{video_length} ) ) {
        if ( process_file( \%previous_value, \%current_value, $file_sub ) ) {
            $file_sub--;
            $file_sub = 0 if $file_sub < 0;
        }
        else {
            $file_sub++;
        }
    }
}

=head2  init
Process parameters and initialize variables
=cut

sub init {

    # **
    my %opts;
    getopts( "d:", \%opts );
    die pod2usage( verbose => 1 ) if $ARGV[0];
    $dir = $opts{'d'} if exists $opts{'d'};
    for my $fn (<$pdir/V*.mp4>) {
        $screen->print_status("Found file from last run ($fn) - removing it");
        unlink $fn or die "Cannot rm $fn";
    }
}

sub main {

    # Process parameters and initialize variables
    init();

    # Get last 8 sections of video processed
    # Put a list of new mp4 files on filesystem into table new_files
    fetch_new_files();    # Puts results into $new_files
    $last_state = fill_buff();
    process_new_files();
}
eval { main() };
close(LOG);
warn if $@;
exit(1) if $@;

#=========================== POD ============================#

=head1 NAME

  identify_videos.pl - Identify new videos and cut points in mp4 input

=head1 SYNOPSIS

  identify_videos.pl [-d directory] 

=head1 ARGUMENTS

=over 4

=item *
<directory>	Directory to process for new video files (instead of default)

=item *
  <unit_test>	Unit test to run

=back

=head1 SEE ALSO

  -

=head1 COPYRIGHT

  Dave Lane (April 2020)

=cut
