package Plugins::RadioStations::Favorites;

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

sub getDisplayName { 'PLUGIN_RADIOSTATIONS_FAVORITES' }
sub playerMenu { 'RADIO' }
my $registered;

sub initPlugin {
    my $class = shift;
    return if $registered;
    $class->SUPER::initPlugin(
        feed => \&Plugins::RadioStations::Plugin::radioFavoritesFeed,
        tag => 'radiostationsfavorites',
        menu => 'radios',
        weight => 51,
    );
    # OPMLBased/Base also registers the web page and classic player menu.
    $registered = 1;
}

sub webPages {
    my $class=shift;
    my $url='plugins/radiostationsfavorites/index.html';
    Slim::Web::HTTP::CSRF->protectURI($url);
    Slim::Web::Pages->addPageLinks('radios',{$class->getDisplayName=>$url});
    Slim::Web::Pages->addPageFunction($url,\&browsePage);
    require Plugins::RadioStations::NativeEditor;
    Slim::Web::HTTP::CSRF->protectURI('plugins/RadioStations/editor/index.html');
    Slim::Web::Pages->addPageFunction('plugins/RadioStations/editor/index.html',\&Plugins::RadioStations::NativeEditor::indexHandler);
}

sub browsePage {
    my ($client,$params)=@_;
    my $button=Slim::Web::HTTP::filltemplatefile('plugins/RadioStations/browse-controls.html',$params);
    $params->{pageHeaderInfo}=$$button;
    return Slim::Web::XMLBrowser->handleWebIndex({
        client=>$client,
        feed=>\&Plugins::RadioStations::Plugin::radioFavoritesFeed,
        title=>getDisplayName(),
        timeout=>35,
        args=>\@_,
    });
}

sub editorPage {
    my ($client,$params)=@_;
    require Plugins::RadioStations::Settings;
    # Navigation must never resubmit a pending mutation or retain edit state.
    if (($params->{radioView} || '') eq 'browse') {
        delete @{$params}{qw(radioEditing radioEditId radioOpenEdit radioTableAction radioOrderAction saveSettings radioPlay)};
    }
    $params->{radioEditId}=$params->{radioOpenEdit} if ($params->{radioOpenEdit} || '') =~ /^[a-f0-9]{64}$/;
    if ($params->{radioCancelEdit}) { delete $params->{radioEditId} }
    Plugins::RadioStations::Settings::process($client,$params);
    delete $params->{radioEditId} if !$params->{radioTransferError} && ($params->{radioTableAction} || '') =~ /^(update|delete):/;
    if (my $id=$params->{radioPlay}) {
        eval {
            die Slim::Utils::Strings::cstring($client,'PLUGIN_RADIOSTATIONS_SELECT_PLAYER') unless $client;
            my ($item)=grep {$_->{id} eq $id} @{Plugins::RadioStations::Plugin::favoriteItems($client)};
            die 'Station not found' unless $item;
            my $request=Slim::Control::Request::executeRequest($client,['playlist','play',$item->{url},$item->{name}]);
            die 'Playback request failed' if !$request || $request->isStatusError;
            1;
        } or $params->{radioTransferError}="$@";
    }
    $params->{radioEditing}=1 if $params->{radioTableAction} || $params->{radioOrderAction} || $params->{radioEditId};
    $params->{radioPlayerView}=1;
    require URI::Escape;
    my $player=URI::Escape::uri_escape_utf8($params->{player} || '');
    my $root=$params->{webroot} || '/';
    my $browse=$root.'plugins/radiostationsfavorites/index.html?radioView=browse&amp;player='.$player;
    $params->{radioBrowseUrl}=$browse;
    $params->{pwd_list}=[
        {title=>Slim::Utils::Strings::cstring($client,'PLUGIN_RADIOSTATIONS_FAVORITES'),href=>'href="'.$browse.'" target="_self"'},
    ];
    push @{$params->{pwd_list}},{title=>Slim::Utils::Strings::cstring($client,'PLUGIN_RADIOSTATIONS_EDIT')} if $params->{radioEditing};
    $params->{radioStations}=Plugins::RadioStations::Plugin::favoriteItems($client);
    return Slim::Web::HTTP::filltemplatefile('plugins/RadioStations/player.html',$params);
}

1;
