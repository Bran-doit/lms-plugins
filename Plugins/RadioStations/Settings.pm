package Plugins::RadioStations::Settings;
use strict;
use warnings;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Slim::Utils::Favorites;
use Slim::Utils::Strings qw(cstring);
use Plugins::RadioStations::ManualStations;
use Plugins::RadioStations::RadioStore;
my $prefs=preferences('plugin.radiostations');
sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_RADIOSTATIONS') }
sub page { Slim::Web::HTTP::CSRF->protectURI('plugins/RadioStations/settings/basic.html') }
sub handler {
    my ($class,$client,$params)=@_;
    process($client,$params);
    return $class->SUPER::handler($client,$params);
}
sub process {
    my ($client,$params)=@_;
    $params->{saveSettings}=1 if $params->{radioTableAction} || $params->{radioOrderAction};
    eval {
        # Preserve previous multiline entries in the durable store before removing
        # the legacy preference. A failed write leaves the old list untouched.
        my $legacy=$prefs->get('manualStations') || '';
        if (length $legacy) {
            my ($items,$errors)=Plugins::RadioStations::ManualStations::parse($legacy);
            die cstring($client,'PLUGIN_RADIOSTATIONS_MANUAL_ERROR') if @$errors;
            Plugins::RadioStations::RadioStore::add_items($items);
            $prefs->set('manualStations','');
        }
        my $pendingManual=$prefs->get('pendingManual') || [];
        if (@$pendingManual) {
            Plugins::RadioStations::RadioStore::add_items($pendingManual);
            $prefs->set('pendingManual',[]);
        }
        if ($params->{saveSettings}) {
            $prefs->set('autoDetectRadio',$params->{pref_autoDetectRadio} ? 1 : 0) if exists $params->{pref_autoDetectRadio};
            $prefs->set('moveRadioFavorites',$params->{pref_moveRadioFavorites} ? 1 : 0) if exists $params->{pref_moveRadioFavorites};
            my %selection=%{$prefs->get('pendingSelection') || {}};
            for my $key (keys %$params) {
                next unless $key =~ /^radioTouched_([a-f0-9]{64})$/ && $params->{$key};
                $selection{$1}=$params->{'radioPick_'.$1} ? 1 : 0;
            }
            $prefs->set('pendingSelection',\%selection);
            my $action=$params->{radioTableAction} || '';
            if ($action eq 'add') {
                my $url=$params->{radioNewUrl} || ''; my $name=$params->{radioNewName} || '';
                $url =~ s/^\s+|\s+$//g; $name =~ s/^\s+|\s+$//g;
                my ($items,$errors)=Plugins::RadioStations::ManualStations::parse($url);
                die cstring($client,'PLUGIN_RADIOSTATIONS_ADD_ERROR') unless @$items==1 && !@$errors && $items->[0]{url} eq $url && $url !~ /[\r\n]/;
                my $item=$items->[0]; $item->{name}=$name if length $name;
                $item->{id}=Plugins::RadioStations::RadioStore::id($url); $item->{manual}=1;
                Plugins::RadioStations::RadioStore::add_items([$item]);
                $prefs->set('radioFavorites',1); $params->{pref_radioFavorites}=1;
                require Plugins::RadioStations::Favorites;
                Plugins::RadioStations::Favorites->initPlugin;
                $params->{radioNewUrl}=''; $params->{radioNewName}='';
            } elsif ($action eq 'apply') {
                my %selected=map {substr($_,10)=>1} grep {/^radioPick_[a-f0-9]{64}$/ && $params->{$_}} keys %$params;
                my $pending=$prefs->get('pendingManual') || [];
                my @manual=grep {$selected{$_->{id}}} @$pending;
                my $count=Plugins::RadioStations::RadioStore::add_items(\@manual);
                $prefs->set('pendingManual',[grep {!$selected{$_->{id}}} @$pending]);
                my $favorites=Slim::Utils::Favorites->new($client);
                if ($favorites) {
                    $count += $prefs->get('moveRadioFavorites')
                        ? Plugins::RadioStations::RadioStore::move_selected($favorites,\%selected,{})
                        : Plugins::RadioStations::RadioStore::copy_selected($favorites,\%selected,{});
                }
                $params->{radioTransferCount}=$count;
                if ($count) {
                    $prefs->set('radioFavorites',1); $params->{pref_radioFavorites}=1;
                    require Plugins::RadioStations::Favorites;
                    Plugins::RadioStations::Favorites->initPlugin;
                }
            } elsif ($action =~ /^(delete|update):([a-f0-9]{64})$/) {
                my ($operation,$id)=($1,$2);
                my $items=Plugins::RadioStations::RadioStore::load();
                my ($item)=grep {$_->{id} eq $id} @$items;
                die cstring($client,'PLUGIN_RADIOSTATIONS_EDIT_MISSING') unless $item;
                if ($operation eq 'delete') {
                    Plugins::RadioStations::RadioStore::save([grep {$_->{id} ne $id} @$items]);
                } else {
                    my $url=$params->{'radioUrl_'.$id} || '';
                    my $name=$params->{'radioName_'.$id} || '';
                    $url =~ s/^\s+|\s+$//g; $name =~ s/^\s+|\s+$//g;
                    my ($parsed,$errors)=Plugins::RadioStations::ManualStations::parse($url);
                    die cstring($client,'PLUGIN_RADIOSTATIONS_ADD_ERROR') unless @$parsed==1 && !@$errors && $parsed->[0]{url} eq $url;
                    my $newId=Plugins::RadioStations::RadioStore::id($url);
                    die cstring($client,'PLUGIN_RADIOSTATIONS_EDIT_DUPLICATE') if grep {$_->{id} ne $id && $_->{url} eq $url} @$items;
                    if ($url ne $item->{url}) {delete $item->{parser};$item->{type}='audio'}
                    $item->{url}=$url; $item->{name}=length($name) ? $name : $url; $item->{id}=$newId;
                    Plugins::RadioStations::RadioStore::save($items);
                    $prefs->set('favoritesOrder',[map {$_ eq $id ? $newId : $_} @{$prefs->get('favoritesOrder') || []}]);
                }
            } elsif ($action =~ /^restore:([a-f0-9]{64})$/) {
                my $id=$1; my $favorites=Slim::Utils::Favorites->new($client);
                my %excluded=(%{$prefs->get('autoExcluded') || {}},$id=>1);
                $prefs->set('autoExcluded',\%excluded);
                $selection{$id}=0; $prefs->set('pendingSelection',\%selection);
                Plugins::RadioStations::RadioStore::restore_selected($favorites,{$id=>1}) if $favorites;
            } elsif ($action =~ /^discard:([a-f0-9]{64})$/) {
                my $id=$1;
                $prefs->set('pendingManual',[grep {$_->{id} ne $id} @{$prefs->get('pendingManual') || []}]);
            }
            Plugins::RadioStations::Plugin::moveFavorite($client,$params->{radioOrderAction}) if $params->{radioOrderAction};
            Plugins::RadioStations::Plugin::_scheduleRadioScan(2);
        }
        1;
    } or $params->{radioTransferError}="$@";
    eval { $params->{radioTable}=Plugins::RadioStations::Plugin::tableItems($client); 1 }
        or $params->{radioTransferError}="$@";
    $params->{radioManualOrder}=($prefs->get('favoritesSort') || '') eq 'manual';
    return $params;
}
sub prefs {
    return ($prefs,qw(countryOverride maxResults topResults maxTags cacheTTL hideBroken recentCount menuLocation radioFavorites autoDetectRadio moveRadioFavorites));
}
1;

