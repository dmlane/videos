use strict;
{

    package vidData;
    use parent 'Clone';

    sub new {
        my ( $class, $args ) = @_;
        my $self = {
            file       => $args->{file}       || "",
            program    => $args->{program}    || "",
            series     => $args->{series}     || 1,
            episode    => $args->{episode}    || 1,
            section    => $args->{section}    || 0,
            section_id => $args->{section_id} || 0,
            start_time => $args->{start_time} || "hh:mm:ss.ddd",
            end_time   => $args->{end_time}   || "hh:mm:ss.ddd"
        };
        bless $self, $class;
    }
}
1;
