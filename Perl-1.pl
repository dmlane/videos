#require Term::Screen;
#use Term::ANSIScreen  qw/:color :cursor :screen :keyboard/;
use strict;

use Clipboard;
Clipboard->copy('#');
my $res     = "#";
my $default = "01:02:03.004";

sub tsktsk {
    $SIG{INT} = \&tsktsk;
    Clipboard->copy($default);
}
$SIG{INT} = \&tsktsk;
until ( $res =~ /^\d\d:\d\d:\d\d\.\d\d\d/ ) {
    sleep(1);
    $res = Clipboard->paste;
}
print ">>>" . $res . "<<<\n";
