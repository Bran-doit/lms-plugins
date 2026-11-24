use strict;use warnings;use Test::More;use File::Temp qw(tempdir);use lib '.';
BEGIN {
 $INC{'Slim/Plugin/Favorites/Opml.pm'}=__FILE__;
 package Slim::Plugin::Favorites::Opml;
 sub new {bless {},shift}sub toplevel {$_[0]{opml}{body}[0]{outline}}sub error {$_[0]{error}}
 sub title {$_[0]{opml}{head}{title}}sub clearerror {delete $_[0]{error}}
 sub level {my ($self,$index,$contains)=@_;return ($self->toplevel,($contains ? $index : undef))}
 $INC{'Slim/Utils/Prefs.pm'}=__FILE__;
 package Slim::Utils::Prefs;sub import {no strict 'refs';*{caller().'::preferences'}=sub {bless {},'TestPrefs'}}
 package TestPrefs;our %values;sub get {$values{$_[1]}}sub set {$values{$_[1]}=$_[2]}
 $INC{'Slim/Utils/Strings.pm'}=__FILE__;
 package Slim::Utils::Strings;sub import {no strict 'refs';*{caller().'::string'}=sub {$_[0]};*{caller().'::cstring'}=sub {$_[1]}}
 $INC{'Slim/Utils/Log.pm'}=__FILE__;
 package Slim::Utils::Log;sub import {no strict 'refs';*{caller().'::logger'}=sub {bless {},'TestLog'}}
 $INC{'Slim/Music/Info.pm'}=__FILE__;
 package Slim::Music::Info;sub mimeToType {'mp3'}sub isSong {1}
 $INC{'Slim/Web/XMLBrowser.pm'}=__FILE__;
 $INC{'Tie/Cache/LRU.pm'}=__FILE__;
 package Tie::Cache::LRU;sub TIEHASH {bless {},shift}sub FETCH {$_[0]{$_[1]}}sub STORE {$_[0]{$_[1]}=$_[2]}
 package Slim::Web::HTTP;sub filltemplatefile {my $out='native template';return \$out}
 package Plugins::RadioStations::Plugin;
 sub favoriteItems {my $items=Plugins::RadioStations::RadioStore::load();my %rank;my $i=0;$rank{$_}=$i++ for @{$TestPrefs::values{favoritesOrder} || []};return [sort {($rank{$a->{id}}||0)<=>($rank{$b->{id}}||0)} @$items]}
 package main;sub INFOLOG () {0}sub DEBUGLOG () {0}
}
use Plugins::RadioStations::EditorStore;
my $dir=tempdir(CLEANUP=>1);{no warnings 'redefine';*Plugins::RadioStations::RadioStore::path=sub {"$dir/radio.json"}}
Plugins::RadioStations::RadioStore::add_items([{url=>'https://radio.test/a',name=>'Alpha',image=>'https://radio.test/a.png',parser=>'custom'},{url=>'https://radio.test/b',name=>'Beta'}]);
my $editor=Plugins::RadioStations::EditorStore->new;
is(scalar @{$editor->toplevel},2,'existing saved stations appear in native adapter');
is($editor->toplevel->[0]{icon},'https://radio.test/a.png','logo mapped to native icon');
$editor->toplevel->[0]{text}='Renamed';$editor->save;
ok(!$editor->error,'native rename saves');
is(Plugins::RadioStations::RadioStore::load()->[0]{name},'Renamed','rename reaches common store');
is(Plugins::RadioStations::RadioStore::load()->[0]{parser},'custom','rename retains playback parser');
@{$editor->toplevel}=reverse @{$editor->toplevel};$editor->save;
is($TestPrefs::values{favoritesOrder}[0],Plugins::RadioStations::RadioStore::id('https://radio.test/b'),'native drag order propagated');
my $deleted=splice @{$editor->toplevel},0,1;$editor->save;
is(scalar @{Plugins::RadioStations::RadioStore::load()},1,'native cut deletes saved entry');
push @{$editor->toplevel},$deleted;$editor->save;
is(scalar @{Plugins::RadioStations::RadioStore::load()},2,'native paste restores cut entry');
push @{$editor->toplevel},{text=>'New',URL=>'PLUGIN_FAVORITES_URL'};$editor->save;
is(scalar @{Plugins::RadioStations::RadioStore::load()},2,'new placeholder not persisted');
pop @{$editor->toplevel};$editor->save;
is(scalar @{Plugins::RadioStations::RadioStore::load()},2,'cancel new entry preserves stored list');
push @{$editor->toplevel},{text=>'Gamma',URL=>'https://radio.test/c',icon=>'https://radio.test/c.png'};$editor->save;
is(scalar @{Plugins::RadioStations::RadioStore::load()},3,'new native station persists');
my $other=Plugins::RadioStations::EditorStore->new;
Plugins::RadioStations::RadioStore::add_items([{url=>'https://radio.test/external',name=>'External'}]);
$other->toplevel->[0]{text}='Stale';$other->save;
ok($other->error,'concurrent settings change rejects stale editor write');
is(scalar @{Plugins::RadioStations::RadioStore::load()},4,'concurrent station preserved');
$editor=Plugins::RadioStations::EditorStore->new;$editor->toplevel->[0]{URL}='javascript:alert(1)';$editor->save;
ok($editor->error,'invalid URL rejected');
is(scalar @{Plugins::RadioStations::RadioStore::load()},4,'invalid edit preserves original data');
$editor=Plugins::RadioStations::EditorStore->new;$editor->toplevel->[0]{URL}=$editor->toplevel->[1]{URL};$editor->save;
ok($editor->error,'duplicate stream rejected');
require Plugins::RadioStations::NativeEditor;
sub native {my $params=shift;Plugins::RadioStations::NativeEditor::indexHandler(undef,$params,sub {});return $params}
my $page=native({});
is(scalar @{$page->{entries}},4,'native handler renders real stored entries');
my $sess=$page->{sess};
$page=native({sess=>$sess,action=>'edit',index=>0});
ok($page->{entries}[0]{edit},'native inline edit selected');
$page=native({sess=>$sess,action=>'editset',index=>0,entrytitle=>'Native name',entryurl=>'https://radio.test/native',entryicon=>'https://radio.test/native.png'});
is(Plugins::RadioStations::RadioStore::load()->[0]{name},'Native name','native save action uses adapter');
$page=native({sess=>$sess,action=>'move',index=>0,to=>2});
is(Plugins::RadioStations::RadioStore::load()->[2]{name},'Native name','native drag request reorders persistent list');
$page=native({sess=>$sess,action=>'delete',index=>2});
is(scalar @{Plugins::RadioStations::RadioStore::load()},3,'native delete request cuts entry');
$page=native({sess=>$sess,insert=>1});
is(scalar @{Plugins::RadioStations::RadioStore::load()},4,'native paste request restores entry');
$page=native({sess=>$sess,newentry=>1});
is(scalar @{$page->{entries}},5,'new draft visible in editor');
$page=native({sess=>$sess,action=>'editset',index=>4,cancel=>1,removeoncancel=>1});
is(scalar @{$page->{entries}},4,'native cancel removes unsaved draft');
$page=native({sess=>999,action=>'delete',index=>0});
is(scalar @{Plugins::RadioStations::RadioStore::load()},4,'expired session cannot delete another row');
like($page->{errormsg},qr/EXPIRED/,'expired session explained');
done_testing;
