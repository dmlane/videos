use strict;
{

    package myDB;
    use DBI;
    use Try::Tiny;
    use File::Basename;

=head2 read_params
Fetch the parameters from a parameter file using mysql utility. In MariaDB,
this function no longer exists, so I created a dummy script in /usr/local/bin
which produces the same results.
=cut

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
}
{
    #=========================================================================#
    package VidDB;
    use parent -norequire, 'myDB';
    use vidData;

=head2 get_last_values
=cut

    sub get_last_values {
        my ($self) = @_;
        my $res = $self->fetch_row(
            qq(
                    select program_name program,series_number series,episode_number episode,section_number section from
                    videos where raw_status = 0 order by k1,k2 desc limit 1 )
        );
        my $vidres = new vidData($res);
        return $vidres;
    }

    sub add_file {
        my ( $self, %args ) = @_;
        $self->exec(
            qq(insert ignore into raw_file (name,k1,k2,video_length)
                          values('$args{file}','$args{key1}',$args{key2},'$args{video_length}'))
        );
    }

    sub to_vidData {
        my ( $self, $arr );
        my $last_rec = $#{$arr};
        my $rec;
        my @res;
        for ( my $n; $n <= $last_rec; $n++ ) {
            $rec = scalar @{$arr}[$n];
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
        my $result = $self->fetch_row(
            qq(select count(*) db_total_count,count(b.section_number) db_section_count 
                    from  raw_file a
                    left outer join section b on b.raw_file_id =a.id
                    where a.status=0 
                     )
        );
        return $result;
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
            $self->debug("Section already exists and force not set");
            return (1);
        }

        # Delete existing section, as we're replacing it
        if ($section_id) {
            $self->debug("Removing existing section to replace it");
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
}
1;
