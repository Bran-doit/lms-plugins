package Plugins::SearchFocus::I18N;
use strict;
use warnings;
use utf8;
use Exporter qw(import);
our @EXPORT_OK=qw(loc language);
our $LANGUAGE; # Scoped override for standalone tests, never persisted.
sub language {
    my $value=defined($LANGUAGE) ? $LANGUAGE : eval {
        require Slim::Utils::Prefs;
        Slim::Utils::Prefs::preferences('server')->get('language');
    };
    return defined($value) && $value =~ /^de(?:[-_].*)?$/i ? 'de' : 'en';
}
sub loc {
    my ($de,$en,@args)=@_;
    my $text=language() eq 'de' ? $de : $en;
    return @args ? sprintf($text,@args) : $text;
}
1;
