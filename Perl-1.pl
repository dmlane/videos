#require Term::Screen;
#use Term::ANSIScreen  qw/:color :cursor :screen :keyboard/;
use strict;
use Term::ReadKey;

my @arr1 = ( 1, 2, 3, 4, 5 );
my @arr2 = ( 2, 3, 4, 5, 6 );

sub xx
{
    #my ($a,$b)=($_[0],$_[1]);
    my ( $a, $b ) = @_;
    @{$a}[2] = 999;
    print "hello\n";
}
xx( \@arr1, \@arr2 );
print $arr1[2];

