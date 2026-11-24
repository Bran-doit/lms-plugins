package Plugins::LyricTranslator::Settings;
use strict;
use warnings;
use utf8;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Plugins::LyricTranslator::Backend;
use Plugins::LyricTranslator::I18N qw(labels language languageName catalog pair);
sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_LYRICTRANSLATOR') }
sub page { Slim::Web::HTTP::CSRF->protectURI('plugins/LyricTranslator/settings/basic.html') }
sub prefs { return (preferences('plugin.lyrictranslator'),qw(showOriginal autoDownload)); }
sub handler {
    my ($class,$client,$params)=@_;
    if ($params->{saveSettings}) {
        eval {
            my ($source,$target)=pair();
            $source=$params->{lt_source} if defined $params->{lt_source};
            $target=$params->{lt_target} if defined $params->{lt_target};
            Plugins::LyricTranslator::Backend::setLanguages($source,$target);
            Plugins::LyricTranslator::Backend::startSetup() if ($params->{lt_action}||'') eq 'setup';
            1;
        } or $params->{lt_error}="$@";
    }
    $params->{lt}=Plugins::LyricTranslator::Backend::status();
    $params->{lt_labels}=labels();
    $params->{lt_language}=language();
    $params->{lt_languages}=[map {{code=>$_,name=>languageName($_)}} sort {languageName($a) cmp languageName($b)} keys %{catalog()->{languages}}];
    return $class->SUPER::handler($client,$params);
}
1;
