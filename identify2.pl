#!/usr/bin/env perl -w
use strict;
use Pod::Usage;
use DBI;
use MP4::Info;
use Getopt::Std;
use Term::Menus;
use File::Basename;
use Carp qw( croak );

my ($dir) = @ARGV;
$dir = "/System/Volumes/Data/Unix/Videos/Import" unless defined $dir;

my $database = $ENV{"HOME"} . "/data/videos.db";
my $dsn      = "DBI:SQLite:dbname=$database";
my $userid   = "";
my $password = "";
my $dbh      = "";

my $unit_test;

my $fetch_array;
my $all_new;

our $q_get_last8 = qq(
select * from 
   (select program_name,series_number,episode_number,section_number,last_updated,file_name
       from videos order by last_updated desc limit 8)
   order by last_updated asc;
);
our $q_get_new_files = qq(
   select name,video_length,last_updated from  new_files
               where not exists (select '1' from raw_file where raw_file.name=new_files.name)
         order by last_updated
);
use constant maxChoice => 5;
our @old_choice = ("") x maxChoice;

sub init
{
    my %opts;
    getopts( "d:u:", \%opts );
    die pod2usage( verbose => 1 ) if $ARGV[0];
    $dir       = $opts{'d'} if exists $opts{'d'};
    $unit_test = $opts{u}   if exists $opts{'u'};
}

sub expand
{

    # Used to sort files in version order
    my $file = shift;
    $file =~ s{(\d+)}{sprintf "%06d", $1}eg;    # expand all numbers to 6 digits
    return $file;
}

sub connect_db
{
    $dbh = DBI->connect( $dsn, $userid, $password, { RaiseError => 1 } )
        or die $DBI::errstr;
    print "Opened database successfully\n";
}

sub close_db
{
    $dbh->disconnect();
}

sub get_last8
{

    # Retrieve the last 8 sections processed from database
    connect_db();
    my $sth = $dbh->prepare($q_get_last8);
    $sth->execute();
    $fetch_array = $sth->fetchall_arrayref( {} );
    close_db();
}

sub get_new_files
{

    # Fetch all new files into all_new array
    connect_db();
    my $sth = $dbh->prepare($q_get_new_files);
    $sth->execute();
    $all_new = $sth->fetchall_arrayref( {} );
    close_db();
}

sub bright_colour
{
    return chr(27) . '[1;33m' . $_ . chr(27) . '[21;39m';
}

sub dim_colour
{
    return chr(27) . '[2m' . $_ . chr(27) . '[22m';
}

sub high1
{

    # Highlight first character
    my $work = $1;
    $work =~ s/^(.)(.*)/\x1b[0;33m\1\x1b[21;39m\2/;
    return $work;
}

sub what_next
{
    my $prompt = sprintf(
        "What next? (%s, %s, %s, %s, %s or %s\n",
        high1("section"), high1("file"),    high1("Episode"),
        high1("Series"),  high1("Program"), high1("Quit")
    );
    my @current_choice = @_;
    my @delta          = @_;
    for ( my $n = 0; $n < maxChoice; $n++ )
    {
        if ( $current_choice[$n] ne $old_choice[$n] )
        {
            $delta[$n]      = bright_colour( $current_choice[$n] );
            $old_choice[$n] = $current_choice[$n];
        }
        else
        {
            $delta[$n] = dim_colour( $current_choice[$n] );
        }

    }

    ReadMode('cbreak');
    printf("==========\n");
    printf
        "file=$delta[0] Program=$delta[1] Series=$delta[2] Episode=$delta[3] Section=$delta[4]\n";

    printf;
}

sub choose_start_point
{
    my @list;
    foreach ( @{$fetch_array} )
    {
        push(
            @list,
            sprintf(
                "%-32s: %s-%d-%d-%d",
                $_->{file_name},      $_->{program_name}, $_->{series_number},
                $_->{episode_number}, $_->{section_number}
            )
        );
    }
    push( @list, "Continue with new files" );
    my $banner    = "  Please Pick an Item:";
    my $selection = &pick( \@list, $banner );
    die "Quitting as requested" if ( $selection eq "]quit[" );

    print "SELECTION = '$selection'\n";
}

sub fetch_new_files
{
    my ( $stmt, $fn, $info, $vhours, $vmins, $video_length, $epoch_timestamp, $sfn, $rv );

    #Get a list of all files in $dir which haven't already been processed
    connect_db();
    for $fn ( sort { expand($a) cmp expand($b) } <$dir/V*.mp4> )
    {
        $info   = get_mp4info($fn);
        $vhours = int( $info->{MM} / 60 );
        $vmins  = int( $info->{MM} % 60 );
        $video_length
            = sprintf( "%02d:%02d:%02d.%003d", $vhours, $vmins, $info->{SS}, $info->{MS} );
        $epoch_timestamp = ( stat($fn) )[9];
        $sfn             = basename($fn);
        $stmt            = qq(insert or ignore into new_files (name,video_length,last_updated)
	  					values('$sfn',strftime('%H:%M:%f','$video_length'),datetime($epoch_timestamp,'unixepoch','localtime')));
        $rv = $dbh->do($stmt) or die $DBI::errstr;
    }

    # Remove any records which already exist in main tables
    $stmt = qq(delete from  new_files
               where exists (select '1' from raw_file where raw_file.name=new_files.name));
    $rv = $dbh->do($stmt) or die $DBI::errstr;
    close_db();
}

sub process_new_files
{
    get_new_files();
    foreach ( @{$all_new} )
    {

    }

}

sub main
{
    init();

    # Open database
    # Process all new files, with the option of re-processing the last 9 sections

    #get_last8();  # Fetch last 9 sections processed into array $fetch_array
    #choose_start_point();

    #fetch_new_files();
    #process_new_files();
    what_next();
    print "hello\n";
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
