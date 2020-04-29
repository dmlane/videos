#!/usr/bin/env perl -w
use strict;
use Pod::Usage;
use DBI;
use MP4::Info;
use Getopt::Std;
use Term::Menus;
use File::Basename;
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
    my @defaults
        = ( { program_name => "", series_number => 1, episode_number => 1, section_number => 0 } );
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

=head2 process_new_files
=cut

sub process_new_files
{
    my ( $program, $series, $episode, $section ) = ( "", 0, 0, 0 );
    my ($all_new) = @_;
    my $action;
    my $last_values = get_last_values();
    if ( @{$last_values} )
    {
        ( $program, $series, $episode, $section ) = get_last_values();
    }

    foreach my $file ( @{$all_new} )
    {
        #$action=get_action($file,$program,$episode,$section);
        printf "==========\n\n";
        printf
            "file=$file->{name} Program=$program Series=$series Episode=$episode Section=$section\n";
        print $file->{name} . "\n";

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
