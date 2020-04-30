#!/usr/bin/env perl -w
use strict;
use Pod::Usage;
use DBI;
use MP4::Info;
use Getopt::Std;
use Term::Menus;
use File::Basename;
use Term::ReadKey;
use Switch;
use Carp qw( croak );

#=========================================================================#

# Defines where we pick up the new videos (may be overridden by command line option)
my $dir = "/System/Volumes/Data/Unix/Videos/Import";

# Unit test to perform
my $unit_test = 0;

# bits for  for database access
my $database = $ENV{"HOME"} . "/data/videos.db";
my $dsn      = "DBI:SQLite:dbname=$database";
my $userid   = "";
my $password = "";
my $dbh;

sub connect_db
{
    $dbh = DBI->connect( $dsn, $userid, $password, { RaiseError => 1 } )
        or die $DBI::errstr;
}

sub close_db
{
    $dbh->disconnect();
}

#=========================================================================#

=head2 db_fetch
Fetch the results of the select provided into a hash array
=cut

sub db_fetch
{
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

sub get_last8_sections
{
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

sub get_last_values
{
    return db_fetch(
        qq(
                        select program_name,series_number,episode_number,section_number from
                        videos where raw_status = 1 order by k1,k2 desc limit 1 )
    );
}

=head2 fetch_new_files
Insert details of any new files found in $dir into the table new_files. We remove any files
already present in raw_file (as it means they have already been partially or fully processed)
=cut

sub fetch_new_files
{
    my ( $stmt, $fn, $info, $vhours, $vmins, $video_length, $epoch_timestamp, $sfn, $rv, $result,
        $k1, $k2 );

    #Get a list of all files in $dir which haven't already been processed
    connect_db();

    for $fn (<$dir/V*.mp4>)
    {
        $info   = get_mp4info($fn);
        $vhours = int( $info->{MM} / 60 );
        $vmins  = int( $info->{MM} % 60 );
        $video_length
            = sprintf( "%02d:%02d:%02d.%003d", $vhours, $vmins, $info->{SS}, $info->{MS} );
        $epoch_timestamp = ( stat($fn) )[9];
        $sfn             = basename($fn);
        if ( $sfn =~ m/^([^_]*_[^_]*_[^_]*)\./ )
        {
            $k1 = $1;
            $k2 = 0;
        }
        else
        {

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
    printf "There are now %d new files to process\n", scalar @{$result};
    return $result;
}

=head2 process_file
=cut

sub process_file
{
    my ( $previous, $current ) = @_;
    my $prompt = "";
    my $char;
    my $HI    = chr(27) . '[1;33m';
    my $LO    = chr(27) . '[0m';
    my %delta = %{$current};
    my @nm    = ( "file", "Program", "Series", "Episode", "Section" );
    foreach my $key ( keys %{$current} )
    {
        unless ( $current->{$key} eq $previous->{$key} )
        {
            $delta{$key} = $HI . $delta{$key} . $LO;
            $previous->{$key} = $current->{$key};
        }
    }
    printf "File %s Program %s Series %d Episode %d Section %d\n", $delta{file}, $delta{program},
        $delta{series}, $delta{episode}, $delta{section};

    while (1)
    {
        ReadMode('cbreak');
        printf("===========\n${prompt}\n");
        printf "What next? (section, file, Episode, Series, Program, Quit): \n";

        $char = ReadKey(0);
        ReadMode('normal');
        switch ($char)
        {
            case 'P' { $current->{program} = get_program( $current->{program} ) }
            case 'S' { $current->{series}  = get_integer( "Series", $current->{series} ) }
            case 'E'
            {
                $current->{episode} = get_integer( "Episode", $current->{episode} + 1 );
                $current->{section} = 0
            }
            case 'f' { $fn = "#" }
            case 's'
            {
                $current->{section} = get_integer( "section", $current->{section} + 1 );
                $start_time         = "00:00:00.000";
                $end_time           = $video_length;
                while (1)
                {
                    $start_time = get_timestamp( "Start time", $start_time );
                    $end_time   = get_timestamp( "End time",   $end_time );
                    $this_result = "$program,$series,$episode,$section,$start_time,$end_time";
                    printf "\n$this_result --> $info_file\n";
                    ReadMode('cbreak');
                    my $char = " ";
                    printf "OK?";
                    $char = ReadKey(0);
                    ReadMode('normal');
                    last if $char eq "Y" or $char eq "y";
                }
                printf INFO "$this_result\n";
                $lastline = "$fn: $this_result";
                $discard  = shift(@buff);
                push( @buff, $lastline );

            }
            case 'Q'
            {
                unlink $proc_file or die "Cannot rm $proc_file";
                exit(0)
            }
        }
    }

}

=head2 process_new_files
=cut

sub process_new_files
{
    my %previous_value = ( file => "", program => "", series => 1, episode => 1, section => 0 );
    my %current_value  = ( file => "", program => "", series => 1, episode => 1, section => 0 );

    my $prompt;

    my ( $program, $series, $episode, $section ) = ( "", 1, 1, 0 );
    my ($all_new) = @_;
    my $action;
    my $last_values = get_last_values();
    if ( @{$last_values} )
    {
        (   $current_value{program}, $current_value{series},
            $current_value{episode}, $current_value{section}
        ) = get_last_values();
    }

    foreach my $file ( @{$all_new} )
    {
        $current_value{file} = $file->{name};

        #$action=get_action($file,$program,$episode,$section);
        process_file( \%previous_value, \%current_value );

    }
}

=head2  init
Process parameters and initialize variables
=cut

sub init
{
    my %opts;
    getopts( "d:u:", \%opts );
    die pod2usage( verbose => 1 ) if $ARGV[0];
    $dir       = $opts{'d'} if exists $opts{'d'};
    $unit_test = $opts{u}   if exists $opts{'u'};

}

sub main
{

    # Process parameters and initialize variables
    init();

    # Get last 8 sections of video processed
    #our $last8_sections = get_last8_sections();

    # Put a list of new mp4 files on filesystem into table new_files
    my $all_new = fetch_new_files();
    process_new_files($all_new);

    printf("Hello");

}

eval { main() };
warn    if $@;
exit(1) if $@;

#=========================== POD ============================#

=head1 NAME

  identify_videos.pl - Identify new videos and cut points in mp4 input

=head1 SYNOPSIS

  identify_videos.pl [-d directory] [-u unit_test] 

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
