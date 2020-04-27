#require Term::Screen;
#use Term::ANSIScreen  qw/:color :cursor :screen :keyboard/;
use Term::ReadKey;

our $hiText       = chr(27) . '[1;33m]';
our $normalText   = chr(27) . '[0m]';
our $flashingText = chr(27) . '[1;33;5m]';

sub hiFirst {

    # Highlight first character in a string
    my ($text) = $@;

}

my $console = Term::ANSIScreen->new;
$console->Cls();

#setscroll 1,20;
my $prev_fn = "";
our @old_value = ( "", "", "", "", "" );

sub get_response {
    my ( $wchar, $hchar, $wpixels, $hpixels ) = GetTerminalSize();

    #printf "==========\n\n";
    my @new_value = @_;
    my $HI        = chr(27) . '[1;33m';
    $HI = colored ['bold yellow'];
    my $NORMAL_COLOUR = chr(27) . '[0m';

    my @delta = @new_value;
    for ( my $n = 0; $n < 5; $n++ ) {
        if ( $new_value[$n] ne $old_value[$n] ) {
            $delta[$n] = colored( $delta[$n], 'blink yellow' );
        }
        else {
            $delta[$n] = colored( $delta[$n], 'white' );
        }
        $old_value[$n] = $new_value[$n];

    }
    $console->clline();
    SAVEPOSprint
        "file=$delta[0] Program=$delta[1] Series=$delta[2] Episode=$delta[3] Section=$delta[4]";
}

get_response( "aaa", 1, 2, 3, 4 );
ReadMode('cbreak');
my $char = ReadKey(0);
ReadMode('normal');
get_response( "aaa", 1, 3, 3, 4 );
