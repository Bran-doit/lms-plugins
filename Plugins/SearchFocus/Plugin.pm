package Plugins::SearchFocus::Plugin;
use strict;
use warnings;
use utf8;
use Plugins::SearchFocus::I18N qw(loc language);
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::PluginManager;
use Slim::Utils::Scanner::API;
use Plugins::SearchFocus::Engine;
use Plugins::SearchFocus::Genres;
use Plugins::SearchFocus::Names;
use Time::HiRes qw(time);

our $VERSION='0.6.0';
my $prefs=preferences('plugin.searchfocus');
my $log=Slim::Utils::Log->addLogCategory({category=>'plugin.searchfocus',defaultLevel=>'WARN',description=>'PLUGIN_SEARCHFOCUS'});
my ($original,$installed,$supported,$lastError);
my %cache;
my %names=map {$_=>1} qw(tracksSearch albumsSearch artistsSearch playlistSearch quickSearch worksSearch);
my %types=map {$_=>1} qw(track album contributor playlist work);

sub initPlugin {
    $prefs->init({%Plugins::SearchFocus::Engine::DEFAULTS});
    $supported=($::VERSION || '') eq '9.0.3';
    if (main::WEBUI) { require Plugins::SearchFocus::Settings; Plugins::SearchFocus::Settings->new; }
    Slim::Control::Request::addDispatch(['searchfocus','status'],[0,1,0,\&statusQuery]);
    Slim::Control::Request::subscribe(\&clearCache,[['rescan'],['done']]);
    Slim::Utils::Scanner::API->onNewTrack({cb=>\&clearCache});
    Slim::Utils::Scanner::API->onChangedTrack({cb=>\&clearCache});
    Slim::Utils::Scanner::API->onDeletedTrack({cb=>\&clearCache});
    Slim::Utils::Scanner::API->onNewPlaylist({cb=>\&clearCache});
    Slim::Utils::Scanner::API->onDeletedPlaylist({cb=>\&clearCache});
}
sub postinitPlugin {
    Plugins::SearchFocus::Genres::install(\&configuration) if $supported;
    return unless $supported && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::FullTextSearch::Plugin');
    return unless Slim::Plugin::FullTextSearch::Plugin->can('createHelperTable');
    $original=\&Slim::Plugin::FullTextSearch::Plugin::createHelperTable;
    no warnings 'redefine';
    *Slim::Plugin::FullTextSearch::Plugin::createHelperTable=\&helper;
    $installed=1;
    configurationChanged();
}
sub configuration { return {map {$_=>$prefs->get($_)} keys %Plugins::SearchFocus::Engine::DEFAULTS}; }
sub clearCache { %cache=(); }
sub configurationChanged {
    clearCache();
    Slim::Control::Queries::wipeCaches() if Slim::Control::Queries->can('wipeCaches');
}
sub runSearch {
    my ($class,$type,$query)=@_;
    my $config=configuration();
    my $key=join("\x1e",language(),$type,$query,map {$config->{$_}//''} sort keys %$config);
    my $now=time;
    if (!Slim::Music::Import->stillScanning && $cache{$key} && $cache{$key}{expires}>$now) { $lastError=''; return $cache{$key}{result}; }
    clearCache() if keys(%cache)>=16;
    my $result=$type eq 'contributor' && $config->{name_fuzzy} && $config->{artist}
        ? Plugins::SearchFocus::Names->search(Slim::Schema->dbh,$query,$config)
        : Plugins::SearchFocus::Engine->search(Slim::Schema->dbh,$type,$query,$config);
    # Cache only IDs, labels and reasons; never store complete lyrics/comments.
    $cache{$key}={expires=>$now+5,result=>$result} if !Slim::Music::Import->stillScanning && @{$result->{rows}}<=2000;
    $lastError='';
    return $result;
}
sub helper {
    my ($class,$args)=@_;
    return $original->(@_) unless $installed && $prefs->get('enabled') && $names{$args->{name}||''} && $types{$args->{type}||''};
    my $dbh=Slim::Schema->dbh; my $name=$args->{name};
    # TEMP qualified DROP cannot remove a persistent LMS table.
    $dbh->do("DROP TABLE IF EXISTS temp.$name");
    $dbh->do("CREATE TEMPORARY TABLE $name (id INTEGER PRIMARY KEY, fulltextweight INTEGER)");
    my $ok=eval {
        my $result=__PACKAGE__->runSearch($args->{type},$args->{search}//'');
        my $insert=$dbh->prepare("INSERT INTO $name (id,fulltextweight) VALUES (?,?)");
        my $rank=@{$result->{rows}};
        # Distinct descending ranks preserve relevance plus stable ID tie-breaking.
        for my $row (@{$result->{rows}}) { $insert->execute($row->{id},$rank--); }
        1;
    };
    if (!$ok) {
        $dbh->do("DELETE FROM temp.$name");
        $lastError=loc('Die eingeschraenkte Suche ist fehlgeschlagen. Bitte Indexstatus pruefen oder Originalsuche waehlen.','The filtered search failed. Check the index status or select the original search.');
        $log->warn($lastError); # Do not log query text or SQL containing user input.
    }
    # No original 500-candidate truncation: LMS applies library filters/count/page later.
}
sub state {
    my $fts=Slim::Utils::PluginManager->isEnabled('Slim::Plugin::FullTextSearch::Plugin')?1:0;
    return {version=>$VERSION,supported=>$supported?1:0,hook=>$installed?1:0,fulltext=>$fts,
      genre_hook=>Plugins::SearchFocus::Genres::installed(),
      enabled=>$prefs->get('enabled')?1:0,error=>$lastError ? loc('Die eingeschraenkte Suche ist fehlgeschlagen. Bitte Indexstatus pruefen oder Originalsuche waehlen.','The filtered search failed. Check the index status or select the original search.') : '',scanning=>Slim::Music::Import->stillScanning?1:0};
}
sub statusQuery {
    my $request=shift; my $state=state();
    $request->addResult($_,$state->{$_}) for sort keys %$state;
    $request->setStatusDone;
}
sub shutdownPlugin {
    Plugins::SearchFocus::Genres::uninstall();
    if ($installed && \&Slim::Plugin::FullTextSearch::Plugin::createHelperTable == \&helper) {
        no warnings 'redefine';
        *Slim::Plugin::FullTextSearch::Plugin::createHelperTable=$original;
    }
    $installed=0; configurationChanged();
}
1;
