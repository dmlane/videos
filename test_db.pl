#!/usr/bin/env perl -w
use strict;
use videos_db;
const my $HistorySize  => 20;

#-- 1. Test insert and replace

my %new_data1 = (
    file    => "V1221_20200503_173110.mp4",
    program => "Alias",
    series  => 1,
    episode => 2,
    section => 3
);
my @buff = ("") x $HistorySize;
if ( db_add_section( \%new_data1, "00:00:00.000", "05:03:02.123", 0 ) == 1 ) {
    printf("Replace record?");
    db_add_section( \%new_data1, "00:00:00.000", "05:03:02.123", 1 );
}

# Test fetch of last 20 records

$new_data1{program} = "whatever";
$new_data1{section} = 0;

for ( my $n = 30; $n < 61; $n++ ) {
    $new_data1{section}++;
    my $from_secs = $n++;
    my $to_secs   = $n;
    db_add_section( \%new_data1, "00:00:$from_secs.000", "00:00:$to_secs.123", 0 );
}
sub push_buffer {
    my($new_rec)=@_;
    my $n=0;
    for (my $m=1;$m<=$HistorySize;$m++){
        $buff[$n++]=$buff[$m];
    }
    $buff[$HistorySize-1]=$new_rec;    
}
sub fill_buff {
    my $last20  = get_last20_sections();
    my $last_element = $#{$last20};
    my $element;
    for ( my $n = 0; $n <= $last_element; $n++ ) {
        $element = scalar @{$last20}[$n];
        push_buffer( sprintf(
            "%s %s -> %s %s_S%2.2dE%2.2d-%2.2d",
            $element->{file_name},    $element->{start_time},    $element->{end_time},
            $element->{program_name}, $element->{series_number}, $element->{episode_number},
            $element->{section_number}
        ));
    }

    return @{$last20}[$last_element];

}
my $whatever = fill_buff();

#Cleanup
db_exec(qq(delete from program where name="whatever" or name="Alias" ));

printf("hello");
