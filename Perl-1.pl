use Term::Screen;

#use Term::ANSIScreen  qw/:color :cursor :screen :keyboard/;

use strict;

use Clipboard;

my $scr = Term::Screen->new() or die "Cannot run Term::Screen->new";
$scr->clrscr();

my @buff = ("123") x 20;

sub prompt
{
    my ($p) = @_;
    my $rc = $scr->rows();
    my ( $first_sub, $top_left );
    if ( $rc < 22 )
    {
        $first_sub = 22 - $rc;
        $top_left  = 0;
    }
    else
    {
        $first_sub = 0;
        $top_left  = $rc - 22;
    }
    $scr->at( $top_left, 0 )->clreos();
    for ( my $n = $first_sub, my $r = $top_left; $n < 20; $n++, $r++ )
    {
        $scr->at( $r, 0 )->puts( $buff[$n] );
    }
    $scr->at( $rc, 0 )->puts($p);
    my $c = $scr->getch();
    printf ">>>$c<<<\n";
}
my $HI = chr(27) . '[1;33m';
my $MD = chr(27) . '[1;36m';
my $LO = chr(27) . '[0m';
prompt("${HI}He${MD}ll${LO}o");
