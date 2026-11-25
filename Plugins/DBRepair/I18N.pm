package Plugins::DBRepair::I18N;
use strict;
use warnings;
use utf8;
use JSON::XS;
use File::Basename qw(dirname);
use File::Spec;
my ($catalog,%source);
sub language {
    my ($value)=@_;
    return defined($value) && $value =~ /\Ade(?:[-_].*)?\z/i ? 'de' : 'en';
}
sub load {
    return if $catalog;
    open my $fh,'<:raw',File::Spec->catfile(dirname(__FILE__),'i18n.json') or die $!;
    local $/;$catalog=decode_json(<$fh>);close $fh;
    for my $key (sort keys %$catalog) {$source{$catalog->{$key}{de}}=$catalog->{$key}{en} unless $key =~ /^LABEL_/;}
}
sub text {
    my ($language,$key)=@_;load();
    return $catalog->{$key}{language($language)} if exists $catalog->{$key};
    return $key;
}
sub translate {
    my ($language,$value)=@_;return '' unless defined $value;
    load();
    return text($language,'LABEL_'.$value) if exists $catalog->{'LABEL_'.$value};
    return $value if language($language) eq 'de';
    return $source{$value} if exists $source{$value};
    # Known variable messages: preserve IDs, counts and native error suffixes.
    if ($value =~ /\AVergleich abgeschlossen: (\d+) hinzugefuegte URLs, (\d+) entfernte URLs, (\d+) geaenderte Bibliothekszuordnungen, (\d+) mehrdeutige gemeinsame URLs\.\z/) {
        return "Comparison completed: $1 added URLs, $2 removed URLs, $3 changed library memberships, $4 ambiguous shared URLs.";
    }
    if ($value =~ /\AAlte Datenbank gesichert \(([^)]+)\) und entfernt\. LMS startet; vollstaendiger Scan folgt\.\z/) {return "Old database backed up ($1) and removed. LMS is starting; a full scan will follow.";}
    if ($value =~ /\ADatenbankkopie erstellt \(([^)]+)\)\. LMS arbeitet mit der bisherigen Datenbank weiter; kein Neuaufbau angefordert\.\z/) {return "Database copy created ($1). LMS continues with the existing database; no rebuild requested.";}
    for my $prefix (sort {length($b)<=>length($a)} keys %source) {
        next unless length($prefix)>12 && index($value,$prefix)==0;
        my $tail=substr($value,length($prefix));
        return $source{$prefix}.$tail if $tail =~ /\A(?:\s|[.:!])/;
    }
    # Unrecognized SQLite/Windows errors are intentionally kept verbatim.
    return $value;
}
1;
