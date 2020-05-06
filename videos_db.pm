use strict;

use Pod::Usage;
use DBI;
use feature 'switch';
use Const::Fast;
use Try::Tiny;

my $dbh;

# bits for  for database access
my $database = $ENV{"HOME"} . "/data/videos.db";
my $dsn      = "DBI:SQLite:dbname=$database";
my $userid   = "";
my $password = "";

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

=head2 get_last_values
=cut

sub get_last_values {
    return db_fetch(
        qq(
                        select program_name,series_number,episode_number,section_number from
                        videos where raw_status = 1 order by k1,k2 desc limit 1 )
    );
}

sub db_add_new_file {
    my ( $sfn, $k1, $k2, $video_length, $epoch_timestamp ) = @_;
    my $stmt = qq(insert or ignore into raw_file (name,k1,k2,video_length,last_updated,status)
                          values('$sfn','$k1',$k2,strftime('%H:%M:%f','$video_length'),
                                datetime($epoch_timestamp,'unixepoch','localtime'),0));
    my $rv = $dbh->do($stmt) or die $DBI::errstr;
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

sub db_fetch_new_files {
    return db_fetch(
        qq(
        select name,video_length,last_updated from  raw_file
                    where status=0
              order by k1,k2;
              )
    );
}

sub db_add_section {
    my ( $current, $start_time, $end_time, $force ) = @_;
    my $results;
    my $stmt;
    my $already_exists = 0;

    #my %rec = @{$current};
    print $current->{file_name} . "\n";

    #-> file must exist in raw_files
    connect_db();
    $stmt = qq(select count(*) count from raw_file where name="$current->{file_name}");
    my $sth = $dbh->prepare($stmt);
    $sth->execute();
    my $rec = $sth->fetchall_arrayref( {} );
    die "No data found" if @{$rec}[0]->{count} != 1;

    # File exists so check if section exists

    $stmt
        = qq(select * from videos where file_name="$current->{file_name}" and section_number=$current->{section_number};);
    $sth = $dbh->prepare($stmt);
    $sth->execute();
    my $existing_section = $sth->fetchall_arrayref( {} );
    if ( scalar @{$existing_section} != 0 ) {

        #Section already exists
        $already_exists = 1;
        return (1) if ( !$force );
    }

    #--> We are allowed to do this
    $dbh->{AutoCommit} = 0;
    $dbh->{RaiseError} = 1;
    try {

        if ($already_exists) {
           
            $stmt = qq(delete from section where id in (
                    select section_id from videos where file_name="$current->{file_name}"
                    and section_number=$current->{section_number}
                    ));
            $dbh->do($stmt);
        }

        $stmt = qq(insert or ignore into program (name) values ("$current->{program_name}" ));
        $dbh->do($stmt);

        $stmt
            = qq(insert or ignore into series (series_number,program_id) values ("$current->{series_number}",
            (select id from program where name="$current->{program_name}")));
        $dbh->do($stmt);

        $stmt = qq(insert or ignore into episode(episode_number,series_id) values (
        $current->{episode_number},
        (select series_id from videos where program_name="$current->{program_name}"
        and series_number=$current->{series_number})));
        $dbh->do($stmt);

        $stmt
            = qq(insert into section(section_number,episode_id,start_time,end_time,raw_file_id,status)
                    values ($current->{section_number},
                    (select episode_id from videos where program_name="$current->{program_name}"
        and series_number=$current->{series_number} and episode_number=$current->{episode_number}),
        strftime('%H:%M:%f',"$start_time"),strftime('%H:%M:%f',"$end_time")
        ,(select id from raw_file where name="$current->{file_name}"),0
        ));
        $dbh->do($stmt);

        $dbh->commit;

    }
    catch {
        warn "Transaction aborted because $_";    # Try::Tiny copies $@ into $_
                                                  # now rollback to undo the incomplete changes
                                                  # but do it in an eval{} as it may also fail
        eval { $dbh->rollback };

        # add other application on-error-clean-up code here
    };
}

1;

