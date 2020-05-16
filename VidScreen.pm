use strict;
use Term::Screen;
use Clipboard;

package VidScreen;
use Const::Fast;
const our $buffer_size => 200;
const our $HI          => chr(27) . '[1;33m';
const our $MD          => chr(27) . '[1;36m';
const our $LO          => chr(27) . '[0m';

sub new {
    my $class = shift;

    #my $max_buffer = 200;
    my $self = {
        'scr'            => -1,
        'rows'           => -1,
        'cols'           => -1,
        'max_buffer'     => $buffer_size,
        'separator_line' => $buffer_size - 4,
        'status_line'    => $buffer_size - 1,
        'buffer'         => [ (' ') x $buffer_size ],
        'stored_values'  => [ (' ') x 7 ],
        'new_values'     => [ (' ') x 7 ],
        'ansi'           => [ (' ') x 7 ],
        'top_status'     => ' ',
    };
    $self->{scr} = Term::Screen->new()
        or die "Cannot run Term::Screen->new";
    $self->{rows}                              = $self->{scr}->rows();
    $self->{cols}                              = $self->{scr}->cols();
    $self->{buffer}[ $self->{separator_line} ] = "_" x 200;
    $self->{scr}->clrscr();
    bless $self, $class;
    return $self;
}

sub show_values {
    my $self = shift;
    #
    #
    my $n;
    for ( $n = 0; $n < 7; $n++ ) {
        $self->{new_values}[$n] = $_[$n];
        $self->{ansi}[$n]       = $MD;
        $self->{ansi}[$n]       = $HI if $self->{new_values}[$n] ne $self->{stored_values}[$n];
        #
    }
    $self->{top_status} = sprintf(
        "%s%-32s%s %s%20s%s %s%3d%s %s%3d%s %s%3d%s %s%s%s %s%s%s",
        $self->{ansi}[0], $self->{new_values}[0], $MD,
        $self->{ansi}[1], $self->{new_values}[1], $MD,
        $self->{ansi}[2], $self->{new_values}[2], $MD,
        $self->{ansi}[3], $self->{new_values}[3], $MD,
        $self->{ansi}[4], $self->{new_values}[4], $MD,
        $self->{ansi}[5], $self->{new_values}[5], $MD,
        $self->{ansi}[6], $self->{new_values}[6], $MD
    );
    $self->{scr}->at( 0, 0 )->puts( $self->{top_status} )->clreol();
}

sub update_values {
    my $self = shift;
    for ( my $n = 0; $n < 7; $n++ ) {
        $self->{stored_values}[$n] = $self->{new_values}[$n];
    }
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
    $self->{scr}->at( 0, 0 )->puts( $self->{top_status} )->clreol();
}

sub print_status {
    my ( $self, $msg ) = @_;
    my $scr = $self->{scr};
    $self->{buffer}[ $self->{status_line} ] = $msg;
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
