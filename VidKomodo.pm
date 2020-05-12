use strict;
use Term::ReadKey;
use Clipboard;

package VidKomodo;

sub new {
    my $class = shift;
    my $self  = {
        'scr'            => -1,
        'rows'           => 20,
        'cols'           => 80,
        'max_buffer'     => 200,
        'separator_line' => 196,
        'buffer'         => [ (' ') x 200 ],
    };
    bless $self, $class;
    return $self;
}

sub print_screen {
    my ($self) = @_;
}

sub print_status {
    my ( $self, $msg ) = @_;
    print "STATUS: $msg\n";
}

sub scroll_top {
    my ( $self, $msg ) = @_;
    $self->print_screen();
    print "SCROLL: $msg\n";
}

sub get_multi {
    my ( $self, $prompt, $type, $default ) = @_;
    my $string      = "";
    my $full_prompt = "$prompt [${default}]: ";
    my $c;
    while () {
        print "NORMAL: $full_prompt >>>$string<<<\n";
        return "" if $type == 2;
        ReadMode('cbreak');
        $c = ReadKey(0);
        ReadMode('normal');
        my $o = ord($c);
        if ( $o == 127 )    # This should be backspace
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
    print "NORMAL: $prompt \n";
    ReadMode('cbreak');
    my $c = ReadKey(0);
    ReadMode('normal');
    return $c;
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
