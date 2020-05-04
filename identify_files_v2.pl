#!/usr/bin/env perl -w
use strict;
use Pod::Usage;
use DBI;
use MP4::Info;
use Getopt::Std;
#use Term::Menus;
use File::Basename;
use Term::ReadKey;
use feature 'switch';
use Clipboard;
use Const::Fast;
use Carp qw( croak );
use Term::Screen;
no warnings 'experimental::smartmatch';

#=========================================================================#
const my $ReserveLines => 4;
const my $HistorySize  => 20;

# Defines where we pick up the new videos (may be overridden by command line option)
my $dir = "/System/Volumes/Data/Unix/Videos/Import";

# bits for  for database access
my $database = $ENV{"HOME"} . "/data/videos.db";
my $dsn      = "DBI:SQLite:dbname=$database";
my $userid   = "";
my $password = "";
my $dbh;
my $scr = Term::Screen->new() or die "Cannot run Term::Screen->new";
$scr->clrscr();

my @buff = ("123") x $HistorySize;

our ( $geo_hist_top, $geo_hist_start, $geo_seperator, $geo_action1, $geo_action2, $geo_status );

sub get_geometry {
    my $r           = $scr->rows();
    my $total_lines = $ReserveLines + $HistorySize;
    if ( $total_lines >= $r ) {
        $geo_hist_top   = 0;
        $geo_hist_start = $total_lines - $r;
    }
    else {
        $geo_hist_top   = $r - $total_lines;
        $geo_hist_start = 0;
    }

    $geo_seperator = $r - $ReserveLines;
    $geo_action1   = $geo_seperator + 1;
    $geo_action2   = $geo_seperator + 2;
    $geo_status    = $geo_seperator + 3;
}

sub print_history {
    get_geometry();
    #$scr->at( $geo_hist_top, 0 )->clreos();
    for ( my $n = $geo_hist_start, my $r = $geo_hist_top; $n < 20; $n++, $r++ ) {
        $scr->at( $r, 0 )->puts( $buff[$n] );
    }
}

sub get_input {
    my ( $prompt, $numeric, $default ) = @_;
    my $string = "";
    my $c;

    my $full_prompt = "$prompt [${default}]: ";
    print_history();

    while () {
        $scr->at( $geo_action1, 0 )->puts($full_prompt)->clreol()->reverse()->puts($string)
            ->normal();
        $c = $scr->noecho()->getch();
        my $o = ord($c);
        if ( $o == 127 )    # This should be backspace
        {
            $string = substr( $string, 0, -1 ) if length( $string > 0 );
            next;
        }
        last if $c =~ /\r/;
        if ( $c =~ /\d/ or $numeric == 0 ) {
            $string = $string . $c;
        }
    }
    return $default if length($string) == 0;
    return $string;

}

sub status {
    my ($p) = @_;
    get_geometry();
    $scr->at( $geo_status, 0 )->clreol()->puts($p);
}

sub prompt_char {
    my ($full_prompt) = @_;
    print_history();
    my $bot_left = $scr->rows() - 2;

    return $scr->getch();
}

sub connect_db {
    $dbh = DBI->connect( $dsn, $userid, $password, { RaiseError => 1 } )
        or die $DBI::errstr;
}

sub close_db {
    $dbh->disconnect();
}

#=========================================================================#

=head2 db_fetch
Fetch the results of the select provided into a hash array
=cut

sub db_fetch {
    my ($stmt) = @_;
    my $results;
    connect_db();
    my $sth = $dbh->prepare($stmt);
    $sth->execute();
    $results = $sth->fetchall_arrayref( {} );
    close_db();
    return $results;
}

=head2  get_last8
Retrieve the last 8 sections processed from database
=cut

sub get_last8_sections {
    my $q_get_last8 = qq(
	select * from 
	   (select program_name,series_number,episode_number,section_number,last_updated,file_name
	       from videos order by last_updated desc limit 8)
	   order by last_updated asc;
	);
    #
    return ( db_fetch $q_get_last8);
}

=head2 get_last_values
=cut

sub get_last_values {
    return db_fetch(
        qq(
                        select program_name,series_number,episode_number,section_number from
                        videos where raw_status = 1 order by k1,k2 desc limit 1 )
    );
}

=head2 save_results
=cut

sub save_results {

}

=head2 fetch_new_files
Insert details of any new files found in $dir into the table new_files. We remove any files
already present in raw_file (as it means they have already been partially or fully processed)
=cut

sub fetch_new_files {
    my ( $stmt, $fn, $info, $vhours, $vmins, $video_length, $epoch_timestamp, $sfn, $rv, $result,
        $k1, $k2 );
    status("Looking for new files to process");

    #Get a list of all files in $dir which haven't already been processed
    connect_db();

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
        $stmt = qq(insert or ignore into raw_file (name,k1,k2,video_length,last_updated,status)
	  					values('$sfn','$k1',$k2,strftime('%H:%M:%f','$video_length'),
								datetime($epoch_timestamp,'unixepoch','localtime'),0));
        $rv = $dbh->do($stmt) or die $DBI::errstr;
    }

    close_db();

    # Get records into an array
    $result = db_fetch(
        qq(
		select name,video_length,last_updated from  raw_file
		            where status=0
		      order by k1,k2;
			  )
    );
    status( sprintf "There are now %d new files to process", scalar @{$result} );
    return $result;
}

sub get_timestamp {
    my ( $prompt, $default ) = @_;
    my $value = "";
    const our $ctrlC_value => "#ControlC#";

    sub ctrl_c {
        $SIG{INT} = \&ctrl_c;
        Clipboard->copy($ctrlC_value);
    }
    Clipboard->copy("0000000000");
    select()->flush();
    $scr->at( $geo_action1, 0 )
        ->puts("What $prompt [Copy to clipboard or ctrl-c for $default] : $value")->clreol();
    $SIG{INT} = \&ctrl_c;
    until ( $value =~ /^\d\d:\d\d:\d\d\.\d\d\d/ ) {
        sleep(1);
        $value = Clipboard->paste;
        $value = $default if $value eq $ctrlC_value;
    }
    chomp $value;
    $scr->at( $geo_action1, 0 )
        ->puts("What $prompt [Copy to clipboard or ctrl-c for $default] : $value")->clreol();

    $SIG{INT} = 'DEFAULT';

    return $value;
}

sub get_program {
    my ($default) = @_;
    my $value;

    #printf STDERR "What is the program name [$default]";
    $value = get_input( "What is the program name", 0, $default );

    #$value = <STDIN>;
    chomp $value;
    status("Program changed from $default to $value");
    return $default if ( length($value) < 1 );
    return ($value);
}

=head2 process_file
=cut

sub process_file {
    our ( $previous, $current, $video_length ) = @_;
    my $prompt = "";
    my $char;
    my $ichar;
    our $HI = chr(27) . '[1;33m';
    our $MD = chr(27) . '[1;36m';
    our $LO = chr(27) . '[0m';
    my ( $start_time, $end_time );
    our $result;
    my ( $start_new, $end_new );
    our %delta;
    my @nm = ( "file", "Program", "Series", "Episode", "Section" );

    sub print_changes {
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

        
        $result= sprintf "File %s Program %s Series %s Episode %s Section %s:", $delta{file},
            $delta{program},
            $delta{series}, $delta{episode}, $delta{section};
        return $result;
    }
OUTER: while (1) {
        $char = prompt_char( print_changes() );

        
        my $saved;
        given ($char) {
            when (/[bB]/) { last OUTER; }
            when ('P') {
                $current->{program} = get_program( $current->{program} );
            }
            when ('S') {
                $saved = $current->{series};
                $current->{series} = get_input( "Series", 1, $saved );
                status("Series changed from $saved to $current->{series} ");
            }

            when ('E') {
                $saved = $current->{episode};
                $current->{episode} = get_input( "Episode", 1, $saved + 1 );
                status("Series changed from $saved to $current->{episode} ");
                $current->{section} = 0;
            }
            when ('f') { last OUTER; }
            when ('s') {
                $current->{section} = get_input( "section", 1, $current->{section} + 1 );
                $start_time         = "00:00:00.000";
                $end_time           = $video_length;
            INNER: while (1) {
                    $start_new = get_timestamp( "Start time", $start_time );
                    $end_new   = get_timestamp( "End time",   $end_time );
                    $ichar     = prompt_char("$start_new -> $end_new     Y=OK (B=Back)?");
                    last INNER if $ichar =~ "[yYbB]";
                }
                if ( $ichar =~ "[yY]" ) {
                    save_results( $current, $start_new, $end_new );
                    $start_time = $start_new;
                    $end_time   = $end_new;
                }
            }
            when (/[qQ]/) {

                #unlink $proc_file or die "Cannot rm $proc_file";
                exit(0);
            }

        }
    }
    return 1 if ( $char =~ "[bB]" );    # Go back to previous file
    return 0;
}

=head2 process_new_files
=cut

sub process_new_files {
    my %previous_value = ( file => "", program => "", series => 1, episode => 1, section => 0 );
    my %current_value  = ( file => "", program => "", series => 1, episode => 1, section => 0 );

    my $prompt;
    my $file_sub;
    my $file;

    my ( $program, $series, $episode, $section ) = ( "", 1, 1, 0 );
    my ($all_new) = @_;
    my $action;
    my $last_values = get_last_values();
    if ( @{$last_values} ) {
        (   $current_value{program}, $current_value{series},
            $current_value{episode}, $current_value{section}
        ) = get_last_values();
    }
    $file_sub = 0;
    while ( $file_sub < @{$all_new} ) {
        $file = @{$all_new}[$file_sub];
        $current_value{file} = $file->{name};
        if ( process_file( \%previous_value, \%current_value, $file->{video_length} ) ) {
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
    my %opts;
    getopts( "d:", \%opts );
    die pod2usage( verbose => 1 ) if $ARGV[0];
    $dir = $opts{'d'} if exists $opts{'d'};

}

sub main {

    # Process parameters and initialize variables
    init();

    # Get last 8 sections of video processed
    #our $last8_sections = get_last8_sections();

    # Put a list of new mp4 files on filesystem into table new_files
    my $all_new = fetch_new_files();
    process_new_files($all_new);

}

eval { main() };
warn    if $@;
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
