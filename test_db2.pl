#!/usr/bin/env perl
use strict;
use File::Basename;
use lib dirname(__FILE__);
use VidDB;
my $p  = $ENV{"PATH"};
my $c1 = new VidDB( "test", "testdb" );    # Databse , login-path
my $cnt;

print "$c1  ->{dsn}\n$c1->{user},$c1->{password}\n";
print $c1->db_fetch_one(" select count(*) from raw_file");

# Create some new files
sub create_new_files {
    for ( my $n = 1000; $n < 1050; $n++ ) {
        $c1->db_add_new_file( "abc_${n}.mp4", "abc", $n, "10:11:12.123" );
    }
}
foreach my $t ( 'program', 'raw_file' ) {
    $c1->db_execute("delete from $t ");
}
$cnt = $c1->db_fetch(qq( select count(*) num_rows from raw_file));
printf "Rows after cleanup=%s\n", $cnt->[0]->{num_rows};
$c1->db_connect();

# Test rollback works
$c1->db_set_autocommit(0);
create_new_files();
$cnt = $c1->db_fetch(qq( select count(*) num_rows from raw_file));
printf "Rows before rollback=%s\n", $cnt->[0]->{num_rows};
$c1->{dbh}->rollback();
$cnt = $c1->db_fetch(qq( select count(*) num_rows from raw_file));
printf "Rows after rollback=%s\n", $cnt->[0]->{num_rows};
create_new_files();
$c1->{dbh}->commit();
$cnt = $c1->db_fetch(qq( select count(*) num_rows from raw_file));
printf "Rows after commit=%s\n", $cnt->[0]->{num_rows};
$c1->db_close();

# Create a full entry
my %new_data1 = (
    file    => "abc_1001.mp4",
    program => "Alias",
    series  => 1,
    episode => 2,
    section => 3
);
my $res = $c1->db_add_section( \%new_data1, "00:00:00.000", "05:03:02.123", 0 );
$res = $c1->db_add_section( \%new_data1, "00:00:00.000", "15:00:00.0", 0 );
$res = $c1->db_add_section( \%new_data1, "00:00:00.000", "15:00:00.0", 1 );
print $res;
