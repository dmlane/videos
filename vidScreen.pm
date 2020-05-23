use strict;
{

    package vidScreen;

    # use Exporter;
    use Term::Screen;
    use Term::ANSIColor qw(colored);
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
    our $prev_section_id      = -1;
    our $first_display_values = 0;

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
        my ( $self, $current_file ) = @_;
        my $msg;
        $current_file = "AnyOldThing#=" unless defined $current_file;
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
            my $msg = substr( $buffer[$n], 0, $cols );
            if ( index( $buffer[$n], $current_file ) != -1 ) {
                $msg = colored( $msg, "green" );
            }
            else {
                $msg = colored( $msg, "blue" );
            }
            $scr->at( $y++, 0 )->puts($msg)->clreol();
        }
        $scr->at( ++$y, 0 )->puts( substr( $separator, 0, $cols ) );
    }

    sub scroll {
        my ( $self, $rec ) = @_;
        my $msg;
        if ( $rec->{section_id} < $prev_section_id ) {
            $msg = "-" x 80;
            shift @buffer;
            push @buffer, $msg;
        }
        $msg = sprintf "%7d: %-30s %s -> %s %s_S%2.2dE%2.2d-%2.2d",
            $rec->{section_id}, $rec->{file}, $rec->{start_time}, $rec->{end_time},
            $rec->{program}, $rec->{series}, $rec->{episode},
            $rec->{section};
        shift @buffer;
        push @buffer, $msg;
        $self->display_screen( $rec->{file} );
        $prev_section_id = $rec->{section_id};
    }

    sub display_values {
        my $color = chr(27) . '[1;33m';
        my $none  = chr(27) . '[0m';
        my $low   = chr(27) . '[0;34m';
        my ( $self, $new_values, $section_count ) = @_;
        if ( $first_display_values == 0 ) {
            $stored_values        = clone $new_values;
            $first_display_values = 1;
        }
        $scr->at( $rows, 0 )->clreol();
        foreach my $k (@keys) {
            if ( $new_values->{$k} eq $stored_values->{$k} ) {
                $scr->puts( colored( $new_values->{$k}, "white" ) );
            }
            else {
                $scr->puts( colored( $new_values->{$k}, "green" ) );
            }
            $scr->puts(", ");
        }
        $scr->puts(" (#sections=$section_count)");
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
            $self->display_screen();    # Inefficient, but ensures it works even if screen resized
            $scr->at( $rows - 2, 0 )->puts($full_prompt)->clreol()->reverse()->puts($string)
                ->normal();
            return "" if $type == 2;
            $c = $scr->noecho()->getch();
            my $o = ord($c);
            if ( $o == 127 )            # This should be backspace
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
        my $msg = "";
        $self->display_screen( $current_values->{file} );
        foreach my $bits ( split( "&", $prompt ) ) {
            $msg = $msg . colored( substr( $bits, 0, 1 ), "yellow underline" ) . substr( $bits, 1 );
        }
        $scr->at( $rows - 2, 0 )->puts($msg)->clreol();
        return $scr->getch();
    }

    sub get_yn {
        my ( $self, $prompt ) = @_;
        my $c = 'x';
        $self->display_screen();
        until ( $c =~ "[yYnN]" ) {
            $scr->at( $rows - 2, 0 )->puts($prompt)->clreol();
            $c = $scr->getch();
        }
        return lc($c);
    }

    sub get_timestamp {
        my ( $self, $field, $default_value ) = @_;
        my $value = "";
        my $prompt
            = sprintf( "What is the %s [%s]: (Clipboard or ctrl-c):", $field, $default_value );
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
                $self->display_status("Start time cannot be greater than stop time");
                next;
            }
            my $res = $self->get_char( sprintf( "Create section %s -> %s? [y|n|b]? ", @value ) );
            if ( $res =~ "[bB]" ) {
                @value = ();
                return @value;
            }
            return @value if $res =~ "[yY]";
        }
    }
}
1;
