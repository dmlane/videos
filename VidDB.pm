use strict;

package VidDB;

use File::Basename;
use lib dirname(__FILE__);
use DBI;
use File::Copy qw(copy);
use Try::Tiny;
use Const::Fast;
use vidData;

const our $logfile_dir => $ENV{"HOME"} . "/data";
our %env_params = (
    TEST => {
        login_path => "testdb",
        database   => "test",
        log        => "test.log"
    },
    PROD => {
        login_path => "videos",
        database   => "videos",
        log        => "videos.log"
    }
);
our $gEnvironment;
our $log_opened = 0;

sub import {
    my ( $self, $env ) = @_;
    if ( defined $env ) {
        unless ( $env eq 'PROD'
            or $env eq 'TEST' )
        {
            printf "Invalid environment '$env' in 'use $self'\n";
            exit(1);
        }
        $gEnvironment = $env;
    }
    else {
        $gEnvironment = 'TEST';
    }
}

=head2 read_params
Fetch the parameters from a parameter file using mysql utility. In MariaDB,
this function no longer exists, so I created a dummy script 
which produces the same results.
=cut

sub read_params {
    my ($login_path) = @_;
    my %arr;
	my $cmd=$ENV{"HOME"} . "/dev/videos/my_print_defaults";
	die "$cmd missing" unless -e $cmd;
    open( PARAMS, $cmd . " -s ${login_path}|" );
    while (<PARAMS>) {
        chomp;
        m/^\w*--([^=]*)=\s*([^\s]*)\s*$/;
        $arr{$1} = $2;
    }
    close(PARAMS);
    return %arr;
}

sub log {
    my ( $self, $rec ) = @_;
    if ( $log_opened == 0 ) {
        my $logfile      = "$logfile_dir/$env_params{$gEnvironment}->{log}";
        my $modtime      = ( stat($logfile) )[9];
        my $logfile_copy = "$logfile." . $modtime;
        if ( -e $logfile ) {
            copy $logfile, $logfile_copy or die "Cannot make backup copy of log";
            utime( undef, $modtime, $logfile_copy );
        }
        open( LOG, '>>', $logfile ) or die "Cannot open log file $logfile";
        $log_opened = 1;
    }
    printf LOG "%7.7d,%s,%s,%s,%s,%2.2d,%2.2d,%2.2d\n",
        $rec->{section_id}, $rec->{file}, $rec->{start_time}, $rec->{end_time},
        $rec->{program}, $rec->{series}, $rec->{episode},
        $rec->{section};
}

sub new {
    my ($class) = @_;
    my $self = {
        database  => $env_params{$gEnvironment}->{database},
        connected => 0,
        dbh       => "",
        read_params( $env_params{$gEnvironment}->{login_path} )
    };
    if ( $gEnvironment eq "TEST" ) {
        warn "Using TEST database\n";
        sleep(2);
    }
    bless $self, $class;
}

sub destroy {
    close LOG if $log_opened == 1;
}

sub connect {
    my $self = shift;
    return
        if $self->{connected} == 1;
    $self->{dbh} = DBI->connect(
        sprintf(
            "DBI:MariaDB:database=%s;host=%s;port=%s",
            $self->{database}, $self->{host}, $self->{port}
        ),
        $self->{user},
        $self->{password},
        { RaiseError => 1, AutoCommit => 0 }
    ) or die $DBI::errstr;
    $self->{connected} = 1;
}

sub disconnect {
    my $self = shift;
    return
        if $self->{connected} == 0;
    $self->{dbh}->commit();
    $self->{dbh}->disconnect();
    $self->{connected} = 0;
}

# sub db_set_autocommit {
#     my ( $self, $value ) = @_;
#     $self->{dbh}->{AutoCommit} = $value;
# }
sub exec {
    my ( $self, $stmt ) = @_;
    my $results;
    my $conn = $self->{connected};    # Store state so that we know what to do later
    $self->connect() if $conn == 0;
    try {
        my $sth = $self->{dbh}->prepare($stmt);
        $sth->execute();
    }
    catch {
        die ">>>Error found executing\n---\n$stmt\n---\n";
    };
    $self->disconnect() if $conn == 0;
    return $results;
}

=head2 fetch
Fetch the results of the select provided into a hash array
=cut

sub fetch {
    my ( $self, $stmt ) = @_;
    my $results;
    my $conn = $self->{connected};    # Store state so that we know what to do later
    $self->connect() if $conn == 0;
    try {
        my $sth = $self->{dbh}->prepare($stmt);
        $sth->execute();
        $results = $sth->fetchall_arrayref( {} );
    }
    catch {
        die ">>>Error found executing\n---\n$stmt\n---\n";
    };
    $self->disconnect() if $conn == 0;
    return $results;
}

sub fetch_number {
    my ( $self, $stmt ) = @_;
    my $results = $self->fetch($stmt);
    return ( values( %{ $results->[0] } ) )[0];
}

sub fetch_row {
    my ( $self, $stmt ) = @_;
    my $results = $self->fetch($stmt);
    return %{$results}[0];
}

#=========================================================================#
#=========================================================================#

=head2 get_last_values
=cut

sub get_last_values {
    my ($self) = @_;
    my $res = $self->fetch_row(
        qq(
            select program_name program,series_number series,episode_number episode,section_number section 
            from videos where raw_status = 0 order by k1 desc,k2 desc limit 1 )
    );
    my $vidres = new vidData($res);
    return $vidres;
}

sub get_programs {
    my ($self) = @_;
    my $res = $self->fetch(qq(select name from program order by name));
    return $res;
}

sub add_file {
    my ( $self, %args ) = @_;
    $self->exec(
        qq(
            insert ignore into raw_file (name,k1,k2,video_length)
            values('$args{file}','$args{key1}',$args{key2},'$args{video_length}'))
    );
}

sub to_vidData {
    my ( $self, @arr ) = @_;
    my $last_rec = @arr;
    my $rec;
    my @res;
    for ( my $n; $n < $last_rec; $n++ ) {
        $rec = scalar $arr[$n];
        $res[$n] = new vidData($rec);
    }
    return @res;
}

=head2  get_last8
Retrieve the last 8 sections processed from database
=cut

sub get_last20_sections {
    my ($self) = @_;
    my $res = $self->fetch(
        qq(
            select A.* from 
                (select program_name program,series_number series,episode_number episode,
                section_number section, last_updated,file_name file, start_time,end_time 
                from videos order by last_updated desc limit 20)  A
            order by last_updated asc
    
    )
    );

    # Put it into our standard format
    return ( self->to_vidData($res) );
}

sub get_file_sections {
    my ( $self, $file_name ) = @_;
    my $stmt = qq(select program_name program,series_number series,episode_number episode,
                section_number section, last_updated,file_name file, start_time,end_time,
                section_id from videos where file_name ="$file_name" order by start_time asc);
    my @res  = @{ $self->fetch($stmt) };
    my @res2 = $self->to_vidData(@res);
    return (@res2);
}

sub fetch_new_files {
    my ($self) = @_;
    return $self->fetch(
        qq( 
        select a.name file,a.video_length,a.last_updated,count(b.section_number) section_count
        from  raw_file a
            left outer join section b on b.raw_file_id =a.id
            where a.status=0 
            group by a.name
              order by k1,k2;
              )
    );
}

sub get_new_file_status {
    my ($self) = @_;
    my $result = $self->fetch_number(
        qq(select count(*) 
                    from  raw_file a 
                    where a.status=0 
                     )
    );
    return $result;
}

sub delete_file {
    my ( $self, $file_name ) = @_;
    $self->exec(qq(update raw_file set status=99 where name="$file_name"));
}

sub delete_section {
    my ( $self, $id ) = @_;
    $self->exec(qq(delete from section where id=$id ));
}

sub add_section {
    my ( $self, $force, $args ) = @_;
    $self->connect();

    # Check file exists in raw_file
    my $raw_id = $self->fetch_number(qq(select id from raw_file where name="$args->{file}"));
    die "Could not find '$args->{file}' in raw_file" unless $raw_id;

    # File exists so check if section exists
    my $section_id = $self->fetch_number(
        qq(select section_id from videos where program_name="$args->{program}" and
                series_number=$args->{series} and
                episode_number=$args->{episode} and
                section_number=$args->{section})
    );
    if ( $section_id and !$force ) {
        return (1);
    }

    # Delete existing section, as we're replacing it
    if ($section_id) {
        $self->exec(qq(delete from section where id=$section_id));
    }
    #
    $self->exec(qq(insert ignore into program (name) values ("$args->{program}" )));
    my $program_id = $self->fetch_number(qq(select id from program where name= "$args->{program}"));
    #
    $self->exec(
        qq(insert ignore into series (series_number,program_id)
                    values ($args->{series},$program_id))
    );
    my $series_id = $self->fetch_number(
        qq(select id from series where program_id=$program_id and
                                         series_number= $args->{series})
    );
    #
    $self->exec(
        qq(insert  ignore into episode(episode_number,series_id) values (
                    $args->{episode},$series_id))
    );
    my $episode_id = $self->fetch_number(
        qq(select id from episode where series_id=$series_id and
                                         episode_number= $args->{episode})
    );
    #
    $self->exec(
        qq(insert into section(section_number,episode_id,start_time,end_time,raw_file_id,status)
                    values ($args->{section}, $episode_id , "$args->{start_time}","$args->{end_time}", $raw_id,0) )
    );
    #
    $args->{section_id} = $self->fetch_number(
        qq(
            select id from section
            where section_number=$args->{section} and episode_id=$episode_id 
            and raw_file_id=$raw_id
        )
    );
    #
    $self->disconnect();
}

#----------------------------------------------------------------------------------------
# For diagnostic routines
sub get_ordered_sections {
    my ($self) = @_;

    # Get a list of all programs and episodes with a total time
    return $self->fetch(
        qq(select section_id,program_name,series_number,episode_number,section_number,time_to_sec(start_time) start_time,time_to_sec(end_time) end_time,k1,k2,
                        time_to_sec(end_time)-time_to_sec(start_time) duration
                    from videos where episode_status=0
                    order by program_name,series_number,episode_number,section_number)
    );
}

sub get_outliers {
    my ($self) = @_;
    return $self->fetch(
        qq(select program_name,series_number,episode_number from outliers order by program_name,series_number,episode_number;
    )
    );
}
1;
