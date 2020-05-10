use strict;
use DBI;
use feature 'switch';

package VidDB;

sub new {
    my ( $class, $database, $login_path ) = @_;
    my ( $user, $password, $host, $port ) = ("") x 4;
    open( PARAMS, "my_print_defaults -s ${login_path}|" );
    while (<PARAMS>) {
        my ( $key, $value ) = split /=/;
        given ($key) {
            when "--user"     { $user     = $value }
            when "--password" { $password = $value }
            when "--host"     { $host     = $value }
            when "--port"     { $port     = $value }
        }
    }
    close(PARAMS);
    my $dsn =

        my $self = {
        'dsn'      => "DBI:MariaDB:database=$database;host=$host;port=$port",
        'user'     => $user,
        'password' => $password,
        'dbh'      => "",

        };

    bless $self, $class;
}

sub db_connect {
    my ($self) = @_;
    $self->{dbh}
        = DBI->connect( $self->{dsn}, $self->{user}, $self->{password}, { RaiseError => 1 } )
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
