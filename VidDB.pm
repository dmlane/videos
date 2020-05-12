use strict;

package VidDB;
use DBI;
use Try::Tiny;
use feature 'switch';
no warnings 'experimental::smartmatch';
our $dsn;

sub read_params {
    my ($login_path) = @_;
    my ( $user, $password, $host, $port ) = ("") x 4;
    open( PARAMS, "/usr/local/bin/my_print_defaults -s ${login_path}|" );
    while (<PARAMS>) {
        chomp;
        my ( $key, $value ) = split /=/, $_, 2;
        given ($key) {
            when ("--user")     { $user     = $value }
            when ("--password") { $password = $value }
            when ("--host")     { $host     = $value }
            when ("--port")     { $port     = $value }
        }
    }
    close(PARAMS);
    return ( $user, $password, $host, $port );
}

sub new {
    my ( $class, $database, $login_path ) = @_;
    my ( $user, $password, $host, $port ) = read_params($login_path);
    my $self = {
        'dsn'       => "DBI:MariaDB:database=$database;host=$host;port=$port",
        'user'      => $user,
        'password'  => $password,
        'dbh'       => "",
        'connected' => 0,
    };
    bless $self, $class;
}

sub db_connect {
    my ($self) = @_;
    $self->{dbh}
        = DBI->connect( $self->{dsn}, $self->{user}, $self->{password}, { RaiseError => 1 } )
        or die $DBI::errstr;
    $self->{connected} = 1;
    return;
}

sub db_close {
    my ($self) = @_;
    $self->{dbh}->disconnect();
    $self->{connected} = 0;
    return;
}

sub db_set_autocommit {
    my ( $self, $value ) = @_;
    $self->{dbh}->{AutoCommit} = $value;
}

sub db_execute {
    my ( $self, $stmt ) = @_;
    $self->db_connect() if $self->{connected} == 0;
    my $sth = $self->{dbh}->prepare($stmt);
    $sth->execute();
    $self->db_close() if $self->{connected} == 0;
}

=head2 db_fetch
Fetch the results of the select provided into a hash array
=cut

sub db_fetch {
    my ( $self, $stmt ) = @_;
    my $results;
    $self->db_connect() if $self->{connected} == 0;
    my $sth = $self->{dbh}->prepare($stmt);
    $sth->execute();
    $results = $sth->fetchall_arrayref( {} );
    $self->db_close() if $self->{connected} == 0;
    return $results;
}

#=========================================================================#

=head2 get_last_values
=cut
sub get_last_values {
    my ($self) = @_;
    return $self->db_fetch(
        qq(
                        select program_name,series_number,episode_number,section_number from
                        videos where raw_status = 1 order by k1,k2 desc limit 1 )
    );
}

sub db_add_new_file {
    my ( $self, $sfn, $k1, $k2, $video_length, $epoch_timestamp ) = @_;
    my $stmt = qq(insert ignore into raw_file (name,k1,k2,video_length)
                          values('$sfn','$k1',$k2,'$video_length'));
    my $rv = $self->{dbh}->do($stmt) or die $DBI::errstr;
}

=head2  get_last8
Retrieve the last 8 sections processed from database
=cut

sub get_last20_sections {
    my ($self) = @_;
    my $last20_sections = qq(
   select A.* from 
       (select program_name,series_number,episode_number,section_number,last_updated,file_name,
        start_time,end_time
           from videos  order by last_updated desc limit 20)  A
       order by last_updated asc;
    
    );
    #
    return ( $self->db_fetch($last20_sections) );
}

sub db_fetch_new_files {
    my ($self) = @_;
    return $self->db_fetch(
        qq(
        select a.name,a.video_length,a.last_updated,count(b.section_number) section_count from  raw_file a
            left outer join section b on b.raw_file_id =a.id
            where a.status=0
            group by a.name
              order by k1,k2;
              )
    );
}

sub db_add_section {
    my ( $self, $current, $start_time, $end_time, $force ) = @_;
    my $results;
    my $stmt;
    my $already_exists = 0;

    #my %rec = @{$current};
    print $current->{file} . "\n";

    #-> file must exist in raw_files
    $self->db_connect();
    $self->db_set_autocommit(0);
    $stmt = qq(select count(*) count from raw_file where name="$current->{file}");
    my $sth = $self->{dbh}->prepare($stmt);
    $sth->execute();
    my $rec = $sth->fetchall_arrayref( {} );
    die "No data found" if @{$rec}[0]->{count} != 1;

    # File exists so check if section exists
    $stmt
        = qq(select * from videos where file_name="$current->{file}" and section_number=$current->{section};);
    $sth = $self->{dbh}->prepare($stmt);
    $sth->execute();
    my $existing_section = $sth->fetchall_arrayref( {} );
    my $num_results      = scalar @{$existing_section};
    if ( $num_results != 0 ) {

        #Section already exists
        $already_exists = 1;
        if ( !$force ) {
            $self->{dbh}->rollback();
            return (1);
        }
    }

    #--> We are allowed to do this
    #$self->{dbh}->{RaiseError} = 1;
    try {
        if ($already_exists) {
            $stmt = qq(delete from section where id in (
                    select section_id from videos where file_name="$current->{file}"
                    and section_number=$current->{section}
                    ));
            $self->{dbh}->do($stmt);
        }
        $stmt = qq(insert ignore into program (name) values ("$current->{program}" ));
        $self->{dbh}->do($stmt);
        $stmt
            = qq(insert ignore into series (series_number,program_id) values ("$current->{series}",
            (select id from program where name="$current->{program}")));
        $self->{dbh}->do($stmt);
        $stmt = qq(insert  ignore into episode(episode_number,series_id) values (
        $current->{episode},
        (select series_id from videos where program_name="$current->{program}"
        and series_number=$current->{series})));
        $self->{dbh}->do($stmt);
        $stmt
            = qq(insert into section(section_number,episode_id,start_time,end_time,raw_file_id,status)
                    values ($current->{section},
                    (select episode_id from videos where program_name="$current->{program}"
        and series_number=$current->{series} and episode_number=$current->{episode}),
        "$start_time","$end_time",(select id from raw_file where name="$current->{file}"),0
        ));
        $self->{dbh}->do($stmt);
        $self->{dbh}->commit();
    }
    catch {
        warn "Transaction aborted because $_";    # Try::Tiny copies $@ into $_
                                                  # now rollback to undo the incomplete changes
                                                  # but do it in an eval{} as it may also fail
        eval { $self->{dbh}->rollback() };
        return 1;

        # add other application on-error-clean-up code here
    }
    finally {
        return 0;
    };
    return 0;
}
1;
