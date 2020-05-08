use strict;
use Term::Screen;

package VidScreen;

sub new {
    my $class = shift;
    my $scr   = Term::Screen->new() or die "Cannot run Term::Screen->new";
    $scr->clrscr();
    my $self  = {
        'scr'     => $scr,
        'rows'    => $scr->rows(),
        'cols' => $scr->cols()
    };

    bless $self, $class;
    return $self;
}

sub print_status {
    my ($self,$msg) = @_;
    my $scr=$self->{scr};
    $scr->at($self->{rows},0)->puts($msg)->clreol();
}



1;
