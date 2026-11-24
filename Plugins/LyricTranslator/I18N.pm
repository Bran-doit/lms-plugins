package Plugins::LyricTranslator::I18N;
use strict;
use warnings;
use utf8;
use Exporter qw(import);
use JSON::XS;
use File::Spec;
use File::Basename qw(dirname);
use Slim::Utils::Prefs;
our @EXPORT_OK = qw(loc language labels languageName catalog route pair);
my ($messages,$catalog);
sub readData {
    my ($file)=@_;
    open my $fh,'<:raw',File::Spec->catfile(dirname(__FILE__),'helper',$file) or die "Cannot read $file: $!";
    local $/; my $value=decode_json(<$fh>); close $fh; return $value;
}
sub language { uc(preferences('server')->get('language') || '') eq 'DE' ? 'de' : 'en' }
sub labels {
    $messages ||= readData('messages.json');
    my $lang=language();
    return {map {$_=>$messages->{$_}{$lang}} keys %$messages};
}
sub loc {
    my ($key,@args)=@_;
    my $text=labels()->{$key} || $key;
    return @args ? sprintf($text,@args) : $text;
}
sub catalog { $catalog ||= readData('downloads.json') }
sub languageName {
    my ($code)=@_;
    return loc('auto') if $code eq 'auto';
    my $languages=catalog()->{languages};
    return exists($languages->{$code}) ? $languages->{$code}{language()} : $code;
}
sub pair {
    my $prefs=preferences('plugin.lyrictranslator');
    return ($prefs->get('sourceLanguage') || 'en',$prefs->get('targetLanguage') || 'de');
}
sub route {
    my ($source,$target)=@_;
    my $c=catalog();
    die loc('unsupported_pair') unless defined($source) && defined($target) && ($source eq 'auto' || exists($c->{languages}{$source})) && exists($c->{languages}{$target});
    return [] if $source eq 'auto';
    die loc('same_language') if $source eq $target;
    my @keys=exists($c->{models}{"$source-$target"}) ? ("$source-$target") : ("$source-en","en-$target");
    die loc('unsupported_pair') if grep {!exists $c->{models}{$_}} @keys;
    return \@keys;
}
1;
