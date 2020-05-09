#!/usr/bin/env perl
use strict;
use File::Basename;
use lib dirname(__FILE__);
use VidScreen;

my $c1 = new VidScreen;
$c1->print_status("Helloooooo");
for ( my $n = 0; $n < 300; $n++ ) {
    $c1->scroll_top( sprintf("Line $n") );

}
my $c = ' ';
while ( $c ne 'W' ) {

    $c = $c1->get_char("Give me a W: ");

}
my $n = $c1->get_number( "Give me a number: ", 301156 );

$c1->print_status("Number=$n");
$n = $c1->get_number( "Give me a number: ", 301156 );

$c1->print_status("Number=$n");
for (my $a=0;$a<5;$a++){
           $c1->print_status($c1->get_string("Give me a string","20 rue de l'Ouest"));
           
}