#!/usr/bin/env perl
use strict;
{

    package myDB;
    use DBI;
    use Try::Tiny;
    use File::Basename;
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
            debug     => $args->{debug} || 0,
            read_params( $args->{login_path} || "testdb" )
        };
        warn "Using TEST database\n" if $self->{database} eq "test";
        bless $self, $class;
    }

    sub debug {
        my ( $self, $msg ) = @_;
        if ( $self->{debug} ) {
            my ( $package, $filename, $line ) = caller;
            printf( "%s:%4d:%s\n", basename($filename), $line, $msg );
        }
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
        my $conn = $self->{connected}
            ;    # Store state so that we know what to do later
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
        my $conn = $self->{connected}
            ;    # Store state so that we know what to do later
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

    package vidData {
        use parent 'Clone';

        sub new {
            my ( $class, $args ) = @_;
            my $self = {
                file       => $args->{filename}   || "",
                program    => $args->{program}    || "",
                series     => $args->{series}     || -1,
                episode    => $args->{episode}    || -1,
                section    => $args->{section}    || -1,
                start_time => $args->{start_time} || "hh:mm:ss.ddd",
                end_time   => $args->{end_time}   || "hh:mm:ss.ddd"
            };
            bless $self, $class;
        }
    }
}
{

    package VidDB {
        use parent -norequire, 'myDB';

        sub get_last_values {
            my ($self) = @_;
            $self->debug("Fetching last values");
            my $res = $self->fetch_row(
                qq(
                    select program_name program,series_number series,episode_number episode,section_number section from
                    videos where raw_status = 0 order by k1,k2 desc limit 1 )
            );
            my $vidres = new vidData($res);
            return $vidres;
        }

        sub get_new_files {
            my ($self) = @_;
            my $result = $self->fetch(
                qq(select a.name file,a.video_length,a.last_updated,count(b.section_number) section_count 
                    from  raw_file a
                    left outer join section b on b.raw_file_id =a.id
                    where a.status=0 
                    group by a.name
                    order by k1,k2)
            );
            return $result;
        }
        sub get_new_file_status {
         my ($self) = @_;
            my $result = $self->fetch_row(
                qq(select count(*) total_count,count(b.section_number) section_count 
                    from  raw_file a
                    left outer join section b on b.raw_file_id =a.id
                    where a.status=0 
                     )
            );   
            return $result;
        }

        sub add_file {
            my ( $self, $args ) = @_;
            $self->exec(
                qq(insert ignore into raw_file (name,k1,k2,video_length)
                          values('$args->{file}','$args->{key1}',$args->{key2},'$args->{video_length}'))
            );
        }

        sub add_section {
            my ( $self, $force, $args ) = @_;
            $self->connect();

            # Check file exists in raw_file
            my $raw_id
                = $self->fetch_number(
                qq(select id from raw_file where name="$args->{file}"));
            die "Could not find '$args->{file}' in raw_file" unless $raw_id;

            # File exists so check if section exists
            my $section_id = $self->fetch_number(
                qq(select section_id from videos where program_name="$args->{program}" and
                series_number=$args->{series} and
                episode_number=$args->{episode} and
                section_number=$args->{section})
            );
            if ( $section_id and !$force ) {
                $self->debug("Section already exists and force not set");
                return (1);
            }

            # Delete existing section, as we're replacing it
            if ($section_id) {
                $self->debug("Removing existing section to replace it");
                $self->exec(qq(delete from section where id=$section_id));
            }
            #
            $self->exec(
                qq(insert ignore into program (name) values ("$args->{program}" ))
            );
            my $program_id
                = $self->fetch_number(
                qq(select id from program where name= "$args->{program}"));
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
            $self->disconnect();
        }

        sub fetch_new_files {
            my ($self) = @_;
            return $self->fetch(
                qq( 
        select a.name file,a.video_length,a.last_updated,count(b.section_number) section_count from  raw_file a
            left outer join section b on b.raw_file_id =a.id
            where a.status=0 
            group by a.name
              order by k1,k2;
              )
            );
        }
    }
}
import VidDB;
#
#my %p = read_params("videos");
my $c
    = new VidDB( { database => "test", login_path => "testdb", debug => 1 } );
my $n = $c->fetch_number(qq(select count(*) from raw_file));
print "Raw_File count=$n\n";
my $r = $c->get_last_values();
print "Done\n";
$c->add_file(
    {   file         => "fred01.mp4",
        key1         => "fred",
        key2         => "01",
        video_length => "01:05:23.129"
    }
);
if ($c->add_section(
        0,
        {   file       => "fred01.mp4",
            program    => "Fred",
            series     => 1,
            episode    => 2,
            section    => 3,
            start_time => "00:01:02.003",
            end_time   => "00:01:05.123"
        }
    )
    )
{
    $c->add_section(
        1,
        {   file       => "fred01.mp4",
            program    => "Fred",
            series     => 1,
            episode    => 2,
            section    => 3,
            start_time => "00:01:02.003",
            end_time   => "00:01:05.123"
        }
    );
}
my $o1 = $c->get_last_values();
print "\nYup\n";
