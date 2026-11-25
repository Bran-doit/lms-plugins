package Plugins::SearchFocus::Settings;
use strict;
use warnings;
use utf8;
use Plugins::SearchFocus::I18N qw(loc language);
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
my $prefs=preferences('plugin.searchfocus');
sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_SEARCHFOCUS') }
sub page { Slim::Web::HTTP::CSRF->protectURI('plugins/SearchFocus/settings/basic.html') }
sub handler {
    my ($class,$client,$params)=@_;
    if ($params->{saveSettings} && !$params->{resetDefaults} && exists $params->{pref_name_aliases}) {
        my $valid=eval {Plugins::SearchFocus::Names::parseAliases($params->{pref_name_aliases}//'');1};
        if (!$valid) {
            my $message=$@; $message =~ s/ at .*? line \d+.*//s;
            $params->{settingsError}=$message;
            $params->{nameAliasesPending}=$params->{pref_name_aliases};
            delete $params->{saveSettings};
        }
    }
    if ($params->{saveSettings}) {
        if ($params->{resetDefaults}) { $prefs->set($_,$Plugins::SearchFocus::Engine::DEFAULTS{$_}) for keys %Plugins::SearchFocus::Engine::DEFAULTS; }
        else {
            for my $key (keys %Plugins::SearchFocus::Engine::DEFAULTS) {
                next if $key =~ /^name_/ && !exists $params->{pref_name_aliases};
                my $v=$params->{'pref_'.$key};
                $v=$key eq 'name_aliases' ? ($v//'')
                    : $key eq 'mode' ? (($v||'') eq 'or'?'or':'and') : ($v?1:0);
                $prefs->set($key,$v);
            }
        }
        Plugins::SearchFocus::Plugin::configurationChanged();
    }
    return $class->SUPER::handler($client,$params);
}
sub beforeRender {
    my ($class,$params)=@_;
    $params->{sfLanguage}=language();
    $params->{focus}=Plugins::SearchFocus::Plugin::configuration();
    $params->{focusState}=Plugins::SearchFocus::Plugin::state();
    $params->{nameAliasesValue}=exists $params->{nameAliasesPending}
        ? $params->{nameAliasesPending} : $params->{focus}{name_aliases};
    my $q=$params->{testQuery}//'';
    $params->{testQuery}=$q;
    if (length $q && $params->{testSearch}) {
        my @groups;
        for my $pair ([genre=>loc('Genres','Genres')],[contributor=>loc('Interpreten','Artists / contributors')],[album=>loc('Alben','Albums')],[track=>loc('Titel','Tracks')],[playlist=>loc('Playlists','Playlists')]) {
            my $result=eval {
                if ($pair->[0] eq 'genre') {
                    my $rows=Slim::Schema->dbh->selectall_arrayref('SELECT id,name AS genre FROM genres',{Slice=>{}});
                    my $ranked=Plugins::SearchFocus::Genres::rank($rows,$q,$params->{focus}{genre_hide_mixed});
                    {rows=>[map {{%$_,label=>Plugins::SearchFocus::Engine::text($_->{genre})}} @$ranked],candidates=>scalar(@$rows),ms=>0};
                } else { Plugins::SearchFocus::Plugin->runSearch($pair->[0],$q); }
            };
            if (!$result) { $params->{testError}=loc('Testsuche fehlgeschlagen. Suchbegriff begrenzen und Volltextindex pruefen.','Test search failed. Shorten the query and check the full-text index.'); last; }
            my @rows=@{$result->{rows}}; my $total=@rows;
            splice(@rows,30) if @rows>30;
            push @groups,{name=>$pair->[1],rows=>\@rows,total=>$total,ms=>$result->{ms},candidates=>$result->{candidates}};
        }
        $params->{testGroups}=\@groups;
    }
}
1;
