use strict;
{

    package myDB;
    use DBI;
    use Try::Tiny;
    #
    sub read_params {
        my ($login_path) = @_;
        my %arr;
        open( PARAMS, "/usr/local/bin/my_print_defaults -s ${login_path}|" );
        while (<PARAMS>) {
            chomp;
            m/^\w*--([^=]*)=\s*([^\s]*)\s*$/;
            $arr{$1} = $2;
        }
        close(PARAMS);
        return %arr;
    }

    sub new {
        my ( $class, $args ) = @_;
        my $self = {
            database  => $args->{database} || "test",
            connected => 0,
            dbh       => "",
            read_params( $args->{login_path} || "testdb" )
        };
        warn "Using TEST database\n" if $self->{database} eq "test";
        bless $self, $class;
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
}
{

    package VidDB {
        use parent -norequire, 'myDB';

        sub get_last_values {
            my ($self) = @_;
            return $self->fetch_row(
                qq(
                    select program_name,series_number,episode_number,section_number from
                    videos where raw_status = 0 order by k1,k2 desc limit 1 )
            );
        }

        sub db_add_section {
            my ( $self, $force, $args ) = @_;
            $self->connect();

            # Check file exists in raw_file
            my $raw_id
                = $self->fetch_number(qq(select id from raw_file where name="$args->{file}"));
            die "Could not find '$args->{file}' in raw_file" unless $raw_id;

            # File exists so check if section exists
            my $section_id = $self->fetch_number(
                qq(select section_id from videos where program_name="$args->{program}" and
                series_number=$args->{series} and
                episode_number=$args->{episode} and
                section_number=$args->{section})
            );
            return (1) if ( $section_id and !$force );

            # Delete existing section, as we're replacing it
            if ($section_id) {
                $self->exec(qq(delete from section where id=$section_id));
            }
            #
            $self->exec(qq(insert ignore into program (name) values ("$args->{program}" )));
            my $program_id
                = $self->fetch_number(qq(select id from program where name= "$args->{program}"));
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
                    $self->{episode},$series_id))
            );
            my $episode_id = qq(select id from episode where series_id=$series_id and
                                         episode_number= $self->{episode})
                ;
            #
            my $episode_id = $self->fetch_number(
                qq(select id from episode where series_id=$series_id and
                                         episode_number= $self->{episode})
            );
            $self->exec(
                qq(insert into section(section_number,episode_id,start_time,end_time,raw_file_id,status)
                    values ($self->{section}, $episode_id , "$start_time","$end_time", $raw_file_id) )
            );
            #
            $self->disconnect();
        }
    }
}
import VidDB;
#
#my %p = read_params("videos");
my $c = new VidDB( { database => "videos", login_path => "videos" } );
my $n = $c->fetch_number(qq(select count(*) from raw_file));
my $r = $c->get_last_values();
print "Done\n";
