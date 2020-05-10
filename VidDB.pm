use strict;
use DBI;

package VidDB;

sub new {
    my ( $class, $flavour, $database, $userid, $password ) = @_;
    my $self = {
        'dbh'      => "",
        'dsn'      => "DBI:MariaDB:database=videos;mysql_read_default_file=$ENV{'HOME'}/.mylogin.cnf",
    };
    bless $self, $class;
}

sub db_connect {
    my ($self) = @_;
    $self->{dbh}
        = DBI->connect( $self->{dsn}, $self->{userid}, $self->{password}, { RaiseError => 1 } )
        or die $DBI::errstr;
    return;
}

sub db_close {

    # This must be overidden
    return;
}

sub db_prepare {
    return;
}

sub db_execute {
    return;
}

#=========================================================================#

=head2 db_fetch
Fetch the results of the select provided into a hash array
=cut

sub db_fetch {
    my ( $self, $stmt ) = @_;
    my $results;
    $self->db_connect();
    $self->db_prepare($stmt);
    $self->db_execute();
    $results = $self->fetchall_arrayref( {} );
    close_db();
    return $results;
}
