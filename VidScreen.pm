use strict;
use Term::Screen;
use Clipboard;

package VidScreen;

sub new {
    my $class = shift;

    #my $max_buffer = 200;
    my $self = {
        'scr'            => -1,
        'rows'           => -1,
        'cols'           => -1,
        'max_buffer'     => 200,
        'separator_line' => 196,
        'buffer'         => [ (' ') x 200 ],
    };
    $self->{scr} = Term::Screen->new()
        or die "Cannot run Term::Screen->new";
    $self->{rows} = $self->{scr}->rows();
    $self->{cols} = $self->{scr}->cols();

    $self->{buffer}[ $self->{separator_line} ] = "_" x 200;
    $self->{scr}->clrscr();
    bless $self, $class;
    return $self;
}

sub print_screen {
    my ($self) = @_;
    $self->{scr}->resize();    # This will tell package to re-check the dimensions
    my $rows = $self->{scr}->rows();
    my $cols = $self->{scr}->cols();
    printf "$rows - $cols\n";

    if ( $rows != $self->{rows} or $cols != $self->{cols} ) {
        $self->{scr}->clrscr();
        $self->{rows}                              = $rows;
        $self->{cols}                              = $cols;
        $self->{buffer}[ $self->{max_buffer} - 1 ] = "Screen resized to $rows x $cols";
    }

    for ( my $r = 0, my $n = $self->{max_buffer} - $rows; $r < $rows; $r++, $n++ ) {

        $self->{scr}->at( $r, 0 )->puts( substr( $self->{buffer}[$n], 0, $cols ) )->clreol();
    }
}

sub print_status {
    my ( $self, $msg ) = @_;
    my $scr = $self->{scr};
    $self->{buffer}[ $self->{max_buffer} - 1 ] = $msg;
    $self->print_screen();
}

sub scroll_top {
    my ( $self, $msg ) = @_;
    my ( $n, $m );
    my $pp;
    for ( $n = 1, $m = 0; $n < $self->{separator_line}; $n++, $m++ ) {
        $self->{buffer}[$m] = $self->{buffer}[$n];
    }
    $self->{buffer}[ $self->{separator_line} - 1 ] = $msg;
    $self->print_screen();

}

sub get_multi {
    my ( $self, $prompt, $type, $default ) = @_;
    my $string      = "";
    my $full_prompt = "$prompt [${default}]: ";
    my $c;
    while () {
        $self->print_screen();    # Inefficient, but ensures it works even if screen resized
        $self->{scr}->at( $self->{rows} - 2, 0 )->puts($full_prompt)->clreol()->reverse()
            ->puts($string)->normal();
        return "" if $type == 2;
        $c = $self->{scr}->noecho()->getch();

        my $o = ord($c);
        if ( $o == 127 )          # This should be backspace
        {

            $string = substr( $string, 0, -1 ) if length($string) > 0;
            next;
        }
        last if $c =~ /\r/;
        if ( $c =~ /\d/ or $type == 0 ) {
            $string = $string . $c;
        }
    }
    return $default if length($string) == 0;
    return $string;
}

sub get_string {
    my ( $self, $prompt, $default ) = @_;
    return $self->get_multi( $prompt, 0, $default );
}

sub get_number {
    my ( $self, $prompt, $default ) = @_;
    return $self->get_multi( $prompt, 1, $default );
}

sub get_char {
    my ( $self, $prompt ) = @_;

    $self->print_screen();
    $self->{scr}->at( $self->{rows} - 2, 0 )->puts($prompt)->clreol();
    return $self->{scr}->getch();
}

sub get_timestamp {
    my ( $self, $prompt, $default ) = @_;
    my $value = "";
    our $ctrlC_value = "#CtrlC-value#";

    sub ctrl_c {
        $SIG{INT} = \&ctrl_c;
        Clipboard->copy($ctrlC_value);
    }
    Clipboard->copy("0000000000");
    select()->flush();
    $self->get_multi( $prompt, 2, $default );
    $SIG{INT} = \&ctrl_c;
    until ( $value =~ /^\d\d:\d\d:\d\d\.\d\d\d/ ) {
        sleep(1);
        $value = Clipboard->paste;
        $value = $default if $value eq $ctrlC_value;
    }
    chomp $value;
    $self->{scr}->at( $self->{rows} - 2, 0 )->puts($prompt)->clreol()->reverse()->puts($value)
        ->normal()->clreol();

    $SIG{INT} = 'DEFAULT';

    return $value;
}
1;
