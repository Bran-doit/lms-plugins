use strict;
use warnings;
use utf8;
use Test::More;
use lib '.';
BEGIN {
    for my $module (qw(Slim/Plugin/OPMLBased Slim/Networking/SimpleAsyncHTTP Slim/Utils/Log Slim/Utils/Strings Slim/Utils/Cache Slim/Utils/Prefs Slim/Utils/Favorites Slim/Control/Request)) {
        $INC{"$module.pm"} = __FILE__;
    }
    package Slim::Plugin::OPMLBased;
    our %menus;
    sub initPlugin { my ($class, %args) = @_; $menus{$class} = \%args; }
    package Slim::Control::Request;
    our @subscriptions;
    sub subscribe { push @subscriptions, [@_] }
    sub client { undef }
    package Slim::Utils::Favorites;
    our @items;
    our $unavailable;
    sub new { $unavailable ? undef : bless {}, shift }
    sub all { \@items }
    package Slim::Utils::Log;
    sub addLogCategory { bless {}, 'TestLog' }
    package Slim::Utils::Strings;
    sub import { no strict 'refs'; *{caller().'::cstring'} = sub { $_[1] }; *{caller().'::string'} = sub { $_[0] }; }
    package Slim::Utils::Prefs;
    sub import { no strict 'refs'; *{caller().'::preferences'} = sub { bless {}, 'TestPrefs' }; }
    package TestPrefs;
    our %values;
    sub get { exists $values{$_[1]} ? $values{$_[1]} : $_[1] eq 'countryOverride' ? 'DE' : undef }
    sub set { $values{$_[1]} = $_[2] }
    sub init {} sub setValidate {}
    package Slim::Utils::Cache;
    our %data;
    sub new { bless {}, shift }
    sub get { $data{$_[1]} }
    sub set { $data{$_[1]} = $_[2] }
    package TestLog;
    sub error {} sub warn {}
    package main;
    sub WEBUI () { 0 }
}
use Plugins::RadioStations::Plugin;
{
    no warnings 'redefine';
    *Plugins::RadioStations::RadioStore::load = sub { [] };
}
SKIP: {
    eval { require Plugins::RadioBrowser::Plugin; 1 } or skip 'Original Radio Browser is not installed', 1;
    isnt(Plugins::RadioStations::Plugin::getDisplayName(), Plugins::RadioBrowser::Plugin::getDisplayName(), 'both plugins load with distinct identities');
}
{
    no warnings 'redefine';
    local *Plugins::RadioStations::Plugin::_resolveBaseUrlAsync = sub {};
    Plugins::RadioStations::Plugin->initPlugin;
}
my $countries = Plugins::RadioStations::Plugin::_countryItems(undef, [
    {name => 'Germany', iso_3166_1 => 'DE', stationcount => 10},
    {name => 'Switzerland', iso_3166_1 => 'CH', stationcount => 20},
]);
is($countries->[0]{url}, \&Plugins::RadioStations::Plugin::listRegions, 'country opens intermediate region level');
is($countries->[1]{passthrough}[0]{country}, 'Switzerland', 'country API name carried through');
my $rows = [
    {name => 'Zürich', country => 'Switzerland', stationcount => 4},
    {name => 'Bern', country => 'Switzerland', stationcount => 2},
    {name => 'Bern', country => 'Germany', stationcount => 1},
    {name => '', country => 'Switzerland', stationcount => 1},
];
my $pt = $countries->[1]{passthrough}[0];
my $items = Plugins::RadioStations::Plugin::_regionItems(undef, $rows, $pt);
is_deeply([map {$_->{name}} @$items], ['Bern (2)', 'Zürich (4)'], 'sorted regions restricted to selected country');
is($items->[1]{passthrough}[0]{code}, 'CH', 'region keeps country code');
{
    no warnings 'redefine';
    my ($path, $result, $calls);
    local *Plugins::RadioStations::Plugin::_apiGet = sub { $path = shift; $calls++; shift->($rows); };
    Plugins::RadioStations::Plugin::listRegions(undef, sub {$result = shift}, {}, $pt);
    like($path, qr{^/json/states/Switzerland/\?}, 'uses country-specific endpoint');
    is($result->{items}[0]{url}, \&Plugins::RadioStations::Plugin::stationsByCountry, 'all-country fallback first');
    is(scalar @{$result->{items}}, 3, 'all stations plus two regions');
    Plugins::RadioStations::Plugin::listRegions(undef, sub {}, {}, $pt);
    is($calls, 1, 'cache reused');
    Plugins::RadioStations::Plugin::listRegions(undef, sub {}, {}, $countries->[0]{passthrough}[0]);
    is($calls, 2, 'cache isolated by country');
    for my $mode ('empty', 'invalid', 'failure') {
        %Slim::Utils::Cache::data = ();
        local *Plugins::RadioStations::Plugin::_apiGet = sub {
            $mode eq 'failure' ? $_[2]->('offline') : $_[1]->($mode eq 'empty' ? [] : {});
        };
        Plugins::RadioStations::Plugin::listRegions(undef, sub {$result = shift}, {}, $pt);
        is($result->{items}[0]{url}, \&Plugins::RadioStations::Plugin::stationsByCountry, "all-country fallback survives $mode response");
        is(scalar @{$result->{items}}, $mode eq 'empty' ? 1 : 2, "$mode feedback without empty region folders");
    }
}
{
    no warnings 'redefine';
    my @request;
    local *Plugins::RadioStations::Plugin::_stationsRequestPaged = sub { @request = @_ };
    Plugins::RadioStations::Plugin::stationsByRegion(undef, sub {}, {}, {code => 'CH', state => 'Zürich & Bern'});
    like($request[3], qr/^countrycode=CH&state=Z%C3%BCrich%20%26%20Bern&stateExact=true/, 'Unicode and country-safe exact search');
    like($request[3], qr/hidebroken=true/, 'broken stream preference preserved');
    my $error;
    Plugins::RadioStations::Plugin::stationsByRegion(undef, sub {$error = shift}, {}, {code => 'CH'});
    is($error->{items}[0]{type}, 'text', 'missing region rejected');
}
my @names = ('Zulu', 'Österreich', 'berlin', 'Ägypten', 'Albania');
my @alphabetical = ('Ägypten', 'Albania', 'berlin', 'Österreich', 'Zulu');
my $stationRows = [map {{name => $_, stationuuid => $_, url => 'https://example.org/'.$_}} @names];
my $sortedStations = Plugins::RadioStations::Plugin::_stationsToOpml(undef, $stationRows);
is_deeply([map {$_->{name}} @$sortedStations], \@alphabetical, 'all station feeds sort alphabetically with umlauts and mixed case');
is_deeply([map {$_->{name}} @$stationRows], \@names, 'sorting does not reorder stored recent history');
my $sortedCountries = Plugins::RadioStations::Plugin::_countryItems(undef, [map {{name => $_, iso_3166_1 => 'DE', stationcount => 1}} @names]);
is_deeply([map {$_->{passthrough}[0]{country}} @$sortedCountries], \@alphabetical, 'country display sorted locally');
my $sortedTags = Plugins::RadioStations::Plugin::_tagItems(undef, [map {{name => $_, stationcount => 1}} @names]);
is_deeply([map {$_->{passthrough}[0]{tag}} @$sortedTags], \@alphabetical, 'genres sorted independently of popularity');
is(Plugins::RadioStations::Plugin::_nameSortKey('Straße'), 'strasse', 'sharp s sorted as ss');
ok(!exists $Slim::Plugin::OPMLBased::menus{'Plugins::RadioStations::Favorites'}, 'favorites folder disabled by default');
ok(scalar(grep {$_->[1][0][0] eq 'favorites'} @Slim::Control::Request::subscriptions), 'LMS heart change notification subscribed');
$TestPrefs::values{radioFavorites} = 1;
{
    no warnings 'redefine';
    local *Plugins::RadioStations::Plugin::_resolveBaseUrlAsync = sub {};
    Plugins::RadioStations::Plugin->initPlugin;
}
is($Slim::Plugin::OPMLBased::menus{'Plugins::RadioStations::Favorites'}{menu}, 'radios', 'enabled folder directly under Radio');
is($Slim::Plugin::OPMLBased::menus{'Plugins::RadioStations::Favorites'}{tag}, 'radiostationsfavorites', 'separate command for favorites folder');
@Slim::Utils::Favorites::items = (
    {title => 'Zulu radio', url => 'https://radio.test/z'},
    {title => 'Äther radio', url => 'https://radio.test/a'},
    {title => 'Local album', url => 'db:album=1'},
    {title => 'Podcast', url => 'https://podcast.test/audio.mp3'},
    {title => 'Duplicate', url => 'https://radio.test/z'},
);
$Slim::Utils::Cache::data{'rs_url:https://radio.test/z'} = 'uuid-z';
$Slim::Utils::Cache::data{'rs_url:https://radio.test/a'} = 'uuid-a';
Plugins::RadioStations::Plugin::_onFavoritesChanged(bless({}, 'Slim::Control::Request'));
is(scalar keys %{$TestPrefs::values{favoriteStationUrls}}, 2, 'heart change persists recognized radio URLs only');
%Slim::Utils::Cache::data = ();
my $favfeed;
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef, sub {$favfeed = shift});
is($favfeed->{items}[0]{type}, 'text', 'unapproved favorites not exposed in radio folder');
my $recognized=Plugins::RadioStations::Plugin::_radioFavoriteItems(undef);
is_deeply([map {$_->{name}} @$recognized], ['Äther radio','Zulu radio'], 'heart recognition survives cache expiry');
is($recognized->[0]{favorites_url}, 'https://radio.test/a', 'recognized URL preserved');
@Slim::Utils::Favorites::items = ($Slim::Utils::Favorites::items[0]);
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef, sub {$favfeed = shift});
is(scalar @{$favfeed->{items}}, 1, 'removing heart immediately removes favorite from folder');
$TestPrefs::values{radioFavorites} = 0;
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef, sub {$favfeed = shift});
is(scalar @{$favfeed->{items}}, 0, 'disabled feed does not expose folder contents');
is(scalar @Slim::Utils::Favorites::items, 1, 'disabling preserves LMS favorites');
$TestPrefs::values{radioFavorites} = 1;
$Slim::Utils::Favorites::unavailable = 1;
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef, sub {$favfeed = shift});
is($favfeed->{items}[0]{type}, 'text', 'missing LMS favorites provider handled');
my ($manual, $invalid) = Plugins::RadioStations::ManualStations::parse("Z Radio | https://stream.test/z?a=1&b=2\r\nhttps://stream.test/plain\n\nÄ Radio | http://192.168.1.5/live\nZ duplicate | https://stream.test/z?a=1&b=2");
is(scalar @$manual, 3, 'manual list supports named and bare URLs and removes exact duplicates');
is_deeply($invalid, [], 'valid HTTP HTTPS and local streams accepted');
is($manual->[0]{url}, 'https://stream.test/z?a=1&b=2', 'stream query preserved exactly');
is($manual->[1]{name}, 'https://stream.test/plain', 'bare URL used as display name');
(undef, $invalid) = Plugins::RadioStations::ManualStations::parse("Wrong\nBad | javascript:alert(1)\nBad | https://\nBad | https://stream.test/a b");
is_deeply($invalid, [1,2,3,4], 'invalid URLs reported by line');
$TestPrefs::values{manualStations} = "Manual Z | https://radio.test/z\nManual A | https://manual.test/a";
$Slim::Utils::Favorites::unavailable = 0;
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef, sub {$favfeed = shift});
is_deeply([map {$_->{name}} @{$favfeed->{items}}], ['Manual A','Manual Z'], 'manual and heart entries merged alphabetically with manual name priority');
$Slim::Utils::Favorites::unavailable = 1;
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef, sub {$favfeed = shift});
is(scalar @{$favfeed->{items}}, 2, 'manual streams work without LMS favorites provider');
$TestPrefs::values{radioFavorites} = 0;
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef, sub {$favfeed = shift});
is(scalar @{$favfeed->{items}}, 0, 'checkbox also controls manual station visibility');
{
    package Slim::Web::Settings;
    sub handler { $_[2] }
    $INC{'Slim/Web/Settings.pm'} = __FILE__;
}
require Plugins::RadioStations::Settings;
{
    no warnings 'redefine';
    my @saved;
    local *Plugins::RadioStations::RadioStore::load=sub {[map {{%$_}} @saved]};
    local *Plugins::RadioStations::RadioStore::save=sub {@saved=map {{%$_}} @{$_[0]}};
    Plugins::RadioStations::Settings->handler(undef,{});
    is(scalar @saved,2,'legacy manual stations migrated');
    is($TestPrefs::values{manualStations},'','legacy preference cleared after save');
    my $form={radioTableAction=>'add',radioNewUrl=>'https://saved.test/live',radioNewName=>'New station'};
    Plugins::RadioStations::Settings->handler(undef,$form);
    ok(!$form->{radioTransferError},'manual station staged');
    my $id=Plugins::RadioStations::RadioStore::id('https://saved.test/live');
    my ($row)=grep {$_->{id} eq $id} @{$form->{radioTable}};
    ok($row->{stored},'manual entry immediately saved');
    is(scalar @saved,3,'manual add needs no Apply');
    Plugins::RadioStations::Settings->handler(undef,{radioOrderAction=>'up:'.$id});
    my @order=map {$_->{id}} @{Plugins::RadioStations::Plugin::tableItems(undef)};
    Plugins::RadioStations::Settings->handler(undef,{radioTableAction=>'apply','radioPick_'.$id=>1});
    is(scalar @saved,3,'apply saves manual station');
    is_deeply([map {$_->{id}} @{Plugins::RadioStations::Plugin::tableItems(undef)}],\@order,'order survives apply');
    ($row)=grep {$_->{id} eq $id} @{Plugins::RadioStations::Plugin::tableItems(undef)};
    ok($row->{stored},'applied station grey');
    my $edit={radioTableAction=>'update:'.$id,'radioName_'.$id=>'Renamed','radioUrl_'.$id=>'https://saved.test/changed'};
    Plugins::RadioStations::Settings::process(undef,$edit);
    ok(!$edit->{radioTransferError},'player editor updates shared storage');
    my $newId=Plugins::RadioStations::RadioStore::id('https://saved.test/changed');
    my ($changed)=grep {$_->{id} eq $newId} @saved;
    is($changed->{name},'Renamed','updated name persisted');
    is_deeply($TestPrefs::values{favoritesOrder},[map {$_ eq $id ? $newId : $_} @order],'URL change retains ranking');
    $edit={radioTableAction=>'update:'.$newId,'radioUrl_'.$newId=>$saved[0]{url}};
    Plugins::RadioStations::Settings::process(undef,$edit);
    like($edit->{radioTransferError},qr/EDIT_DUPLICATE/,'duplicate edit rejected');
    is(scalar @saved,3,'rejected edit preserves stations');
    Plugins::RadioStations::Settings::process(undef,{radioTableAction=>'delete:'.$newId});
    is(scalar @saved,2,'delete removes only selected saved station');
    $edit={radioTableAction=>'update:'.$newId,'radioUrl_'.$newId=>'https://saved.test/new'};
    Plugins::RadioStations::Settings::process(undef,$edit);
    like($edit->{radioTransferError},qr/EDIT_MISSING/,'stale edit cannot recreate deleted station');
    $form={radioTableAction=>'add',radioNewUrl=>'broken'};
    Plugins::RadioStations::Settings->handler(undef,$form);
    like($form->{radioTransferError},qr/ADD_ERROR/,'invalid URL rejected');
    is($form->{radioNewUrl},'broken','invalid input remains editable');
    $TestPrefs::values{manualStations}='Keep | https://keep.test/live';
    local *Plugins::RadioStations::RadioStore::save=sub {die 'disk full'};
    Plugins::RadioStations::Settings->handler(undef,{});
    like($TestPrefs::values{manualStations},qr/^Keep/,'failed migration preserves old data');
    $TestPrefs::values{manualStations}='';
    $TestPrefs::values{favoritesSort}='alpha';
    $TestPrefs::values{pendingSelection}={};
}
my $indexed = Plugins::RadioStations::Plugin::_alphabeticFeed({items => [
    {name=>'Alle Sender', type=>'link', textkey=>' '},
    {name=>'1 Radio', type=>'audio'}, {name=>'9 Radio', type=>'audio'},
    {name=>'Äther', type=>'audio'}, {name=>'Alpha', type=>'audio'},
    {name=>'Berlin', type=>'audio'},
]});
is_deeply($indexed->{indexList}, [[' ',1],['0-9',2],['A',2],['B',1]], 'alphabetic index includes correct action and station counts');
is_deeply([map {$_->{textkey}} @{$indexed->{items}}], [' ','0-9','0-9','A','A','B'], 'anchors match index groups');
is(Plugins::RadioStations::Plugin::_alphabeticFeed({items=>[]})->{indexList}, undef, 'no index for empty feed');
{
    no warnings 'redefine';
    my ($root, $resolved, @paths);
    Plugins::RadioStations::Plugin::handleFeed(undef, sub {$root = shift}, {});
    is($root->{items}[0]{url}, \&Plugins::RadioStations::Plugin::localRegions, 'local-country shortcut opens regions');
    local *Plugins::RadioStations::Plugin::listRegions = sub { $resolved = $_[3] };
    local *Plugins::RadioStations::Plugin::_apiGet = sub {
        push @paths, $_[0];
        $_[1]->([{name=>'Germany', iso_3166_1=>'DE', stationcount=>123}, {name=>'Austria', iso_3166_1=>'AT', stationcount=>45}]);
    };
    %Slim::Utils::Cache::data = ();
    Plugins::RadioStations::Plugin::localRegions(undef, sub {}, {}, {code=>'DE'});
    is_deeply($resolved, {code=>'DE',country=>'Germany',count=>123}, 'configured code resolves before first country-list visit');
    Plugins::RadioStations::Plugin::localRegions(undef, sub {}, {}, {code=>'AT'});
    is($resolved->{country}, 'Austria', 'changing configured country selects its regions');
    is(scalar @paths, 1, 'country resolver reuses cache');
    %Slim::Utils::Cache::data = ();
    local *Plugins::RadioStations::Plugin::_apiGet = sub { $_[2]->('offline') };
    my $fallback;
    Plugins::RadioStations::Plugin::localRegions(undef, sub {$fallback=shift}, {}, {code=>'DE'});
    is($fallback->{items}[0]{url}, \&Plugins::RadioStations::Plugin::stationsByCountry, 'all-country fallback remains available if country lookup fails');
}
$TestPrefs::values{manualStations}="Zulu | https://order.test/z\nAlpha | https://order.test/a\nBeta | https://order.test/b";
$TestPrefs::values{radioFavorites}=1;
Plugins::RadioStations::Plugin::moveFavorite(undef,'up:'.Plugins::RadioStations::RadioStore::id('https://order.test/b'));
is_deeply([map {$_->{name}} @{Plugins::RadioStations::Plugin::favoriteItems(undef)}],['Beta','Alpha','Zulu'],'up moves manual entry in combined order');
Plugins::RadioStations::Plugin::radioFavoritesFeed(undef,sub {$favfeed=shift});
ok(!exists $favfeed->{indexList},'manual order has no misleading alphabetical jump index');
Plugins::RadioStations::Plugin::moveFavorite(undef,'down:'.Plugins::RadioStations::RadioStore::id('https://order.test/b'));
is_deeply([map {$_->{name}} @{Plugins::RadioStations::Plugin::favoriteItems(undef)}],['Alpha','Beta','Zulu'],'down moves entry');
$TestPrefs::values{manualStations}.="\nA new station | https://order.test/new";
is(Plugins::RadioStations::Plugin::favoriteItems(undef)->[-1]{name},'A new station','new entries append after manual order');
Plugins::RadioStations::Plugin::moveFavorite(undef,'alpha');
is(Plugins::RadioStations::Plugin::favoriteItems(undef)->[0]{name},'A new station','alphabetical reset restores A-Z');
my ($pipeName,$pipeErrors)=Plugins::RadioStations::ManualStations::parse('DLF | Debatten | https://order.test/dlf');
is($pipeName->[0]{name},'DLF | Debatten','manual station names may contain pipe');
{
    package Slim::Utils::Timers;
    our @pending;
    sub killTimers {}
    sub setTimer {push @pending, [@_] if ref $_[0] eq 'ARRAY'}
    $INC{'Slim/Utils/Timers.pm'}=__FILE__;
    package Slim::Utils::Favorites;
    sub toplevel {[map {{text=>$_->{title}, URL=>$_->{url}, type=>'audio'}} @Slim::Utils::Favorites::items]}
}
{
    no warnings 'redefine';
    my (@moved,@copied);
    $Slim::Utils::Favorites::unavailable=0;
    $TestPrefs::values{autoDetectRadio}=1;
    $TestPrefs::values{moveRadioFavorites}=0;
    $TestPrefs::values{manualStations}='';
    $TestPrefs::values{autoImported}={};
    $TestPrefs::values{autoExcluded}={};
    $TestPrefs::values{favoriteStationUrls}={};
    %Slim::Utils::Cache::data=();
    @Slim::Utils::Favorites::items=({title=>'Radio',url=>'https://worker.test/radio'},{title=>'Unknown',url=>'https://worker.test/unknown'});
    local *Plugins::RadioStations::Detector::classify=sub {my ($e,$k,$api,$cb)=@_; $cb->({kind=>$e->{name} eq 'Radio' ? 'radio' : 'unknown',reason=>'test'})};
    local *Plugins::RadioStations::RadioStore::copy_selected=sub {push @copied,keys %{$_[1]};return 1};
    local *Plugins::RadioStations::RadioStore::move_selected=sub {
        my ($f,$selected)=@_;push @moved,keys %$selected;
        @Slim::Utils::Favorites::items=grep {!$selected->{Plugins::RadioStations::RadioStore::id($_->{url})}} @Slim::Utils::Favorites::items;return 1;
    };
    my $scan=sub {Plugins::RadioStations::Plugin::_runRadioScan();while(my $t=shift @Slim::Utils::Timers::pending){$t->[2]->($t->[0])}};
    $scan->();
    is(scalar @copied,1,'first recognized station automatically copied');
    is(scalar @Slim::Utils::Favorites::items,2,'copy retains general favorites');
    $scan->();is(scalar @copied,1,'copy happens only once even if destination deleted');
    $TestPrefs::values{moveRadioFavorites}=1;
    $scan->();is(scalar @moved,0,'changing copy to move does not revisit old imports');
    push @Slim::Utils::Favorites::items,{title=>'Radio',url=>'https://worker.test/move'};
    $scan->();is(scalar @moved,1,'new station automatically moved when enabled');
    is(scalar @Slim::Utils::Favorites::items,2,'moved source removed, unknown remains');
    my $url='https://worker.test/restored';my $id=Plugins::RadioStations::RadioStore::id($url);
    $TestPrefs::values{autoExcluded}={$id=>1};
    push @Slim::Utils::Favorites::items,{title=>'Radio',url=>$url};
    $scan->();is(scalar @moved,1,'restored station cannot cause loop');
    my $pending;
    local *Plugins::RadioStations::Detector::classify=sub {$pending=$_[3]};
    push @Slim::Utils::Favorites::items,{title=>'Radio',url=>'https://worker.test/pending'};
    Plugins::RadioStations::Plugin::_runRadioScan();ok($pending,'async detection pending');
    $TestPrefs::values{autoDetectRadio}=0;
    $pending->({kind=>'radio',reason=>'test'});
    while(my $t=shift @Slim::Utils::Timers::pending){$t->[2]->($t->[0])}
    is(scalar @moved,1,'disabled automation blocks in-flight result');
    $TestPrefs::values{autoDetectRadio}=1;
    $scan->();is(scalar @moved,2,'cached positive result imported after enabling');
    push @Slim::Utils::Favorites::items,{title=>'Radio',url=>'https://worker.test/race'};
    Plugins::RadioStations::Plugin::_runRadioScan();
    $TestPrefs::values{autoExcluded}{Plugins::RadioStations::RadioStore::id('https://worker.test/race')}=1;
    $pending->({kind=>'radio',reason=>'test'});
    while(my $t=shift @Slim::Utils::Timers::pending){$t->[2]->($t->[0])}
    is(scalar @moved,2,'restore exclusion rechecked after async detection');
    $TestPrefs::values{autoDetectRadio}=0;
}
{
    no warnings 'redefine';
    local *Slim::Web::HTTP::filltemplatefile=sub {$_[1]};
    local *Slim::Utils::Strings::cstring=sub {$_[1]};
    my $mutations=0;
    local *Plugins::RadioStations::Settings::process=sub {$mutations++ if $_[1]{radioTableAction}};
    local *Plugins::RadioStations::Plugin::favoriteItems=sub {[]};
    my $id='a' x 64;
    my $params={radioView=>'browse',radioEditing=>1,radioEditId=>$id,radioTableAction=>'delete:'.$id,player=>'aa:bb'};
    Plugins::RadioStations::Favorites::editorPage(undef,$params);
    ok(!$params->{radioEditing} && !$params->{radioEditId},'back explicitly exits all edit states');
    is($mutations,0,'back never submits a stale delete');
    is(scalar @{$params->{pwd_list}},1,'browse adds favorites to native home breadcrumb');
    like($params->{radioBrowseUrl},qr/player=aa%3Abb/,'back retains encoded player context');
    $params={radioOpenEdit=>$id};
    Plugins::RadioStations::Favorites::editorPage(undef,$params);
    is($params->{radioEditId},$id,'individual station edit opens');
    ok($params->{radioEditing},'individual edit stays in editor');
    is(scalar @{$params->{pwd_list}},2,'editor has additional breadcrumb');
    $params={radioEditing=>1,radioEditId=>$id,radioCancelEdit=>1};
    Plugins::RadioStations::Favorites::editorPage(undef,$params);
    ok(!$params->{radioEditId} && $params->{radioEditing},'cancel closes inputs and keeps list');
    is($mutations,0,'cancel does not save changed fields');
    $params={radioEditing=>1,radioEditId=>$id,radioTableAction=>'update:'.$id};
    Plugins::RadioStations::Favorites::editorPage(undef,$params);
    ok(!$params->{radioEditId},'successful save closes inline edit');
}
done_testing;


