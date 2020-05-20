use strict;
{

    package vidScreen;

    # use Exporter;
    use Term::Screen;
    use Clipboard;
    use Const::Fast;
    use File::Basename;
    use lib dirname(__FILE__);
    use vidData;

    # our @ISA    = qw(Exporter);
    # our @EXPORT = qw(show_values);
    const my $buffer_size       => 100;
    const my $bottom_free_lines => 4;
    const my $separator         => "_" x 200;
    const my @keys              => qw/file program series episode section/;
    const my $ctrlC_value       => "#CtrlC-value#";

    our @buffer         = ( (' ') x $buffer_size );
    our $current_values = new vidData;
    our $stored_values  = new vidData;
    our $status         = "";
    our $scr;
    our $rows;
    our $cols;

    sub new {
        my $class = shift;
        my $self  = {};
        $scr = Term::Screen->new()
            or die "Cannot run Term::Screen->new";
        $rows = $scr->rows();
        $cols = $scr->cols();
        $scr->clrscr();
        bless $self, $class;
    }

    sub display_status {
        my ( $self, $msg ) = @_;
        $status = $msg;
        my $col_start = $cols - length($status);
        $col_start = 0 if $cols < 0;
        $scr->at( 0, 0 )->clreol()->at( 0, $col_start )->reverse()
            ->puts( substr( $status, 0, $cols ) )->normal();
    }

    sub display_screen {
        my $self = shift;
        $scr->resize();    #Re-check dimensions
        unless ($rows == $scr->rows()
            and $cols == $scr->cols() )
        {
            $rows = $scr->rows();
            $cols = $scr->cols();

            #Clear screen needed?
        }
        my $y         = 1;
        my $start_sub = $buffer_size - $rows + $bottom_free_lines + 1;

        # $self->display_status(">>>rows=$rows,cols=$cols<<<");
        for ( my $n = $start_sub; $n < $buffer_size; $n++ ) {
            $scr->at( $y++, 0 )->puts( $buffer[$n], 0, $cols )->clreol();
        }
        $scr->at( ++$y, 0 )->puts( substr( $separator, 0, $cols ) ); #->clreos();
    }

    sub scroll {
        my ( $self, $msg ) = @_;
        shift @buffer;
        push @buffer, $msg;
        $self->display_screen();
    }

    sub display_values {
        my $color = chr(27) . '[1;33m';
        my $none  = chr(27) . '[0m';
        my $low   = chr(27) . '[0;34m';
        my ( $self, $new_values ) = @_;
        $scr->at( $rows, 0 )->clreol();
        foreach my $k (@keys) {
            if ( $new_values->{$k} eq $stored_values->{$k} ) {
                $scr->puts($low);
            }
            else {
                $scr->puts($color);
            }
            $scr->puts( $new_values->{$k} );
            $scr->puts("$none ");
        }
        $current_values = clone $new_values;
    }

    sub update_values {
        $stored_values = clone $current_values;
    }

   #==========================================================================
   # Input routines
    sub get_multi {
        my ( $self, $prompt, $type, $default ) = @_;
        my $string      = "";
        my $full_prompt = "$prompt [${default}]: ";
        my $c;
        while () {
            $self->display_screen()
                ;   # Inefficient, but ensures it works even if screen resized
            $scr->at( $rows - 2, 0 )->puts($full_prompt)->clreol()->reverse()
                ->puts($string)->normal();
            return "" if $type == 2;
            $c = $scr->noecho()->getch();
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
        $self->display_screen();
        $scr->at( $rows - 2, 0 )->puts($prompt)->clreol();
        return $scr->getch();
    }

    sub get_timestamp {
        my ( $self, $field, $default_value ) = @_;
        my $value  = "";
        my $prompt = sprintf( "What is the %s [%s]: (Clipboard or ctrl-c):",
            $field, $default_value );
        $scr->at( $rows - 2, 0 )->puts($prompt)->clreol();

        sub ctrl_c {
            $SIG{INT} = \&ctrl_c;
            print "^C$default_value^";
            Clipboard->copy($ctrlC_value);
        }
        Clipboard->copy("0000000000");
        select()->flush();

        # $self->get_multi( $prompt, 2, $default_value );
        $SIG{INT} = \&ctrl_c;
        until ( $value =~ /^\d\d:\d\d:\d\d\.\d\d\d$/ ) {
            sleep(1);
            $value = Clipboard->paste;
            $value = $default_value if $value eq $ctrlC_value;
        }
        chomp $value;

        # $scr->at( $rows - 2, 0 )->puts($prompt)->clreol()->reverse()
        #     ->puts($value)->normal()->clreol();
        $SIG{INT} = 'DEFAULT';
        return $value;
    }

    sub millisecs {
        my $ts = shift;
        $ts =~ /(..):(..):(..\....)/;
        return ( ( $1 * 60 + $2 ) * 60 + $3 );
    }

    sub get_start_stop_times {
        my ( $self, @defaults ) = @_;
        my @value;
        my @time_type = qw/Start-time Stop-time/;
        my $prompt;
        while (1) {
            for ( my $n = 0; $n < 2; $n++ ) {
                $value[$n]
                    = $self->get_timestamp( $time_type[$n], $defaults[$n] );
                $self->display_status( $value[$n] );
            }
            if ( $value[0] eq $value[1] ) {

                # Saves having to do a crl-c
                $value[1] = $defaults[1];
            }
            my $delta_secs = millisecs( $value[1] ) - millisecs( $value[0] );
            if ( $delta_secs < 0.000 ) {
                $self->display_status(
                    "Start time cannot be greater than stop time");
                next;
            }
            my $res = $self->get_char(
                sprintf( "Create section %s -> %s? [y|n|b]? ", @value ) );
            if ( $res =~ "[bB]" ) {
                @value = ();
                return @value;
            }
            return @value if $res =~ "[yY]";
        }
    }
}
1;
