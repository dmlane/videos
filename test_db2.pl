#!/usr/bin/env perl
use strict;
use File::Basename;
use lib dirname(__FILE__);
use VidDB;
my $p  = $ENV{"PATH"};
my $c1 = new VidDB( "videos", "videos" );

print "$c1->{dsn}\n$c1->{user},$c1->{password}\n";

#$c1->db_connect();
my $resultes = $c1->db_fetch(
    qq(
                        select program_name,series_number,episode_number,section_number from
                        videos where raw_status = 1 order by k1,k2 desc limit 1 )
);
$c1->db_connect();
$c1->db_add_new_file( "abc_124.mp4", "abc", 124, "10:11:12.123" );
$c1->db_close();
print "Done\n";
