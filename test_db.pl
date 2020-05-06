use strict;
use videos_db;

#-- 1. Test insert and replace

my %new_data1 = (
    file_name      => "V1221_20200503_173110.mp4",
    program_name   => "Alias",
    series_number  => 1,
    episode_number => 2,
    section_number => 3
);

if ( db_add_section( \%new_data1, "00:00:00.000", "05:03:02.123", 0 ) == 1 ) {
    printf("Replace record?");
    db_add_section( \%new_data1, "00:00:00.000", "05:03:02.123", 1 );
}
