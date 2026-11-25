use strict;
use warnings;
use utf8;
use Test::More;
use DBI;
use lib '.';
use Plugins::SearchFocus::I18N ();
BEGIN { $Plugins::SearchFocus::I18N::LANGUAGE='de'; }
use Plugins::SearchFocus::Engine;

my $db=DBI->connect('dbi:SQLite:dbname=:memory:','','',{RaiseError=>1,PrintError=>0,sqlite_unicode=>1});
for my $sql (
 'CREATE TABLE tracks(id INTEGER PRIMARY KEY,title TEXT,album INTEGER,lyrics TEXT)',
 'CREATE TABLE albums(id INTEGER PRIMARY KEY,title TEXT)',
 'CREATE TABLE contributors(id INTEGER PRIMARY KEY,name TEXT)',
 'CREATE TABLE contributor_track(track INTEGER,contributor INTEGER)',
 'CREATE TABLE contributor_album(album INTEGER,contributor INTEGER)',
 'CREATE TABLE genres(id INTEGER PRIMARY KEY,name TEXT)',
 'CREATE TABLE genre_track(track INTEGER,genre INTEGER)',
 'CREATE TABLE comments(track INTEGER,value TEXT)',
 'CREATE TABLE works(id INTEGER PRIMARY KEY,title TEXT,composer INTEGER)',
 'CREATE VIRTUAL TABLE fulltext USING fts4(id,type,w10,w5,w3,w1,matchinfo=fts3)'
) {$db->do($sql)}
my $prefix='X'x32;
sub indexrow { my($id,$type,@fields)=@_; $db->do('INSERT INTO fulltext VALUES (?,?,?,?,?,?)',undef,$prefix.$id,$type,@fields); }
$db->do('INSERT INTO albums VALUES (1,?),(2,?)',undef,'Freunde Album','Ferien');
$db->do('INSERT INTO contributors VALUES (1,?),(2,?),(3,?)',undef,'Die Ärzte','Deine Freunde','Beyoncé');
$db->do('INSERT INTO tracks VALUES (1,?,1,?),(2,?,2,?),(3,?,2,?),(4,?,2,?),(5,?,2,?)',undef,
 'Meine Freunde','lyrikgeheim','Anderes Lied','lyrikgeheim','Mix','',"L'été Straße",'', 'Café','');
$db->do('INSERT INTO contributor_track VALUES (1,1),(2,2),(4,3),(5,3)');
$db->do('INSERT INTO contributor_album VALUES (1,1),(2,2)');
$db->do('INSERT INTO comments VALUES (1,?),(2,?)',undef,'kommentargeheim','zweiterkommentar');
$db->do('INSERT INTO genres VALUES (1,?)',undef,'Rock');
$db->do('INSERT INTO genre_track VALUES (2,1)');
$db->do('INSERT INTO works VALUES (1,?,3)',undef,'Symphonie');
indexrow(1,'track','meine freunde','freunde album','die ärzte die arzte lyrikgeheim kommentargeheim','pfadgeheim');
indexrow(2,'track','anderes lied','ferien rock','deine freunde lyrikgeheim zweiterkommentar','');
indexrow(3,'playlist','mix','','','lyrikgeheim');
indexrow(4,'track',"l été straße l ete strasse",'ferien','beyoncé beyonce','');
indexrow(5,'track','café cafe','ferien','beyoncé beyonce','');
indexrow(1,'album','freunde album','','die ärzte die arzte','lyrikgeheim kommentargeheim');
indexrow(2,'album','ferien','','deine freunde','lyrikgeheim zweiterkommentar');
indexrow(1,'contributor','die ärzte die arzte','','','');
indexrow(2,'contributor','deine freunde','','','');
indexrow(3,'contributor','beyoncé beyonce','','','');
indexrow(1,'work','symphonie beyoncé beyonce','','','');
my %prefs=%Plugins::SearchFocus::Engine::DEFAULTS;
sub result { Plugins::SearchFocus::Engine->search($db,$_[0],$_[1],\%prefs) }
sub ids { [map {$_->{id}} @{result(@_)->{rows}}] }
is_deeply(ids('track','Meine Freunde'),[1],'AND retains exact title');
is_deeply(ids('contributor','Meine Freunde'),[],'AND excludes partial artist');
$prefs{mode}='or';
is_deeply(ids('contributor','Meine Freunde'),[2],'OR finds Deine Freunde');
is_deeply(ids('track','Meine Freunde'),[1,2],'exact title ranks above partial match');
$prefs{mode}='and';
is_deeply(ids('track','lyrikgeheim'),[],'lyrics disabled');
is_deeply(ids('track','Deine Freunde'),[2],'artist remains searchable');
is_deeply(ids('album','lyrikgeheim'),[],'lyrics disabled also for albums');
is_deeply(ids('playlist','lyrikgeheim'),[],'playlist track metadata excluded');
$prefs{lyrics}=1;
is_deeply(ids('track','lyrikgeheim'),[1,2],'lyrics independently enabled');
is_deeply(ids('album','lyrikgeheim'),[1,2],'album lyrics explicitly enabled');
is_deeply(ids('track','kommentargeheim'),[],'comments remain disabled');
$prefs{lyrics}=0; $prefs{comment}=1;
is_deeply(ids('track','kommentargeheim'),[1],'comments independently enabled');
is_deeply(ids('track','lyrikgeheim'),[],'lyrics remain disabled');
$prefs{comment}=0;
is_deeply(ids('track','rock'),[],'genre disabled');
$prefs{genre}=1; is_deeply(ids('track','rock'),[2],'genre enabled');
is_deeply(ids('track','pfadgeheim'),[],'paths never searched');
is_deeply(ids('track','Ferien'),[2,4,5],'album name in track search');
$prefs{album}=0; is_deeply(ids('track','Ferien'),[],'album field disabled'); $prefs{album}=1;
is_deeply(ids('playlist','Mix'),[3],'playlist names');
$prefs{playlist}=0; is_deeply(ids('playlist','Mix'),[],'playlist field disabled'); $prefs{playlist}=1;
is_deeply(ids('work','Symphonie'),[1],'work title');
is_deeply(ids('track','ÄRZTE'),[1],'umlaut and uppercase');
is_deeply(ids('track','arzte'),[1],'accent folded search');
is_deeply(ids('track','cafe'),[5],'accent folded title');
is_deeply(ids('track','Beyonce'),[4,5],'accent folded artist');
is_deeply(ids('track',"  L'été --- Straße "),[4],'punctuation whitespace sharp s');
is_deeply(ids('track','Freunnde'),[],'no unimplemented fuzzy promise');
is_deeply(ids('track',''),[],'empty query');
is_deeply(ids('track','???'),[],'punctuation-only query');
is_deeply(ids('track','missingword'),[],'no matches');
eval {result('track','a'x257)}; like($@,qr/zu lang/,'length bound');
eval {result('track',join(' ',map {'word'.$_} 1..13))}; like($@,qr/Zu viele/,'token bound');
eval {result('evil','foo')}; like($@,qr/Unbekannte/,'category whitelist');
result('track',"x'; DROP TABLE tracks; --");
is($db->selectrow_array('SELECT count(*) FROM tracks'),5,'SQL injection not executed');
my $r=result('track','Meine Freunde')->{rows}[0];
like($r->{reason},qr/Exakter Songtitel/,'explain exact title');
ok(!exists $r->{lyrics},'no full lyrics in result');

# Ranking regressions: grammatical words stay searchable but have less influence.
sub rated {
 my ($fields,$query,$mode)=@_;
 my $terms=Plugins::SearchFocus::Engine::tokens($query);
 return Plugins::SearchFocus::Engine::evaluate($fields,$terms,
   Plugins::SearchFocus::Engine::normal($query),$mode||'or',
   Plugins::SearchFocus::Engine::wordWeights($query,$terms));
}
my $possessive=rated({title=>'Meine Welt'},'Meine Freunde');
my $friend=rated({artist=>'Deine Freunde'},'Meine Freunde');
cmp_ok($friend->{score},'>',$possessive->{score},'Freunde in artist ranks above Meine in title');
is($possessive->{score},200,'capitalized possessive remains low');
is($friend->{score},1360,'capitalized content term plus possessive similarity');
is(rated({title=>'Meine Freunde'},'Meine Freunde')->{score},103500,'exact title retains first rank and auditable score');
is(rated({album=>'Deine Freunde'},'Meine Freunde')->{score},$friend->{score},'album and artist equal');
is(rated({title=>'Deine Freunde'},'Meine Freunde')->{score},$friend->{score},'song title and artist equal');
is(rated({artist=>'Deine Freunde'},'meine freunde')->{score},1160,'lowercase content word plus 60 similarity points');
is(rated({artist=>'Marlon And Freunde'},'meine freunde')->{score},1100,'unrelated artist gets no similarity bonus');
is(rated({title=>'Meine Freunde'},'meine freunde')->{score},103300,'exact lowercase title unchanged');
like($friend->{reason},qr/meine ≈ deine.*\+60 Punkte/,'similarity contribution explained');
ok(!rated({artist=>'Deine Freunde'},'meine freunde','and'),'similarity does not relax AND');
ok(!rated({artist=>'Deine Freunde'},'meine'),'similarity alone does not create results');
for my $pair (['meine','deine'],['meine','meinne'],['meinne','meine'],['meine','miene']) {
 ok(Plugins::SearchFocus::Engine::oneEdit(@$pair),'one substitution/insertion/deletion/transposition');
}
for my $pair (['mein','mein'],['die','dir'],['abcd','abc'],['meine','seins'],['abcd','badc']) {
 ok(!Plugins::SearchFocus::Engine::oneEdit(@$pair),'equal/short/multiple edits excluded');
}
is(rated({title=>'anker deine deine'},'anker meine seine')->{score},1160,'one result word cannot cover two fuzzy terms');
is(rated({title=>'anker deine'},'anker deine meine')->{score},3300,'word reserved by exact match cannot score again');
is(rated({title=>'anker freunde'},'anker freund freunnde')->{score},4200,'prefix matched word cannot score again');
is(rated({title=>'anker aaac baaa'},'anker aaaa aaab')->{score},2300,'augmenting path finds both distinct similar words');
is(rated({title=>'anker deine'},'anker deinee meine')->{score},1700,'competing fuzzy terms prefer larger word weight');
is(rated({title=>'Meine Welt'},'MEINE FREUNDE')->{score},200,'all-caps does not promote possessive');
cmp_ok(rated({title=>'Meine',artist=>'Deine Freunde'},'Meine Freunde')->{score},'>',$friend->{score},'two words across fields beat one word');
ok(!rated({title=>'Meine Welt'},'Meine Freunde','and'),'AND still requires the weak word and content word');
ok(rated({title=>'Meine Welt'},'meine','and'),'possessive-only search still works');
cmp_ok(rated({artist=>'Die'},'Die')->{score},'>',rated({title=>'Die Welt'},'Die')->{score},'exact name containing only article preserved');
cmp_ok(rated({title=>'Freunde'},'Meine Freunde')->{score},'>',rated({lyrics=>'Freunde'},'Meine Freunde')->{score},'lyrics remain weaker than names');
like($friend->{reason},qr/1200.*großgeschrieben.*100 Feldpunkte/,'word and field contributions explained');
my @low=qw(der die das dem den des ein eine einer einen einem eines mein meine meinen meiner meinem meines dein deine sein seine ihr ihren unser unsere euer eure euren eurem eurer eures unsre unsren kein keine);
my $weights=Plugins::SearchFocus::Engine::wordWeights(join(' ',@low),\@low);
ok(!(grep {$weights->{$_}{points}!=100} @low),'articles and possessive inflections consistently weak');
my @names=qw(Meinecke Deutschland Freunde Seinfeld Euring);
my $names=Plugins::SearchFocus::Engine::wordWeights(join(' ',@names),[map {lc} @names]);
ok(!(grep {$names->{lc $_}{points}!=1200} @names),'word list does not match name prefixes');
$prefs{mode}='or';
my $upper=ids('track','Meine Freunde');
my $lower=ids('track','meine freunde');
is_deeply([sort @$upper],[sort @$lower],'case changes ranking only, not matching set');
$prefs{mode}='and';
for my $id (100..700) {
 $db->do('INSERT INTO tracks VALUES (?,?,2,?)',undef,$id,"Gemeinsam $id",'');
 indexrow($id,'track',"gemeinsam $id",'ferien','','');
}
is(scalar @{ids('track','gemeinsam')},601,'no 500 candidate cutoff');
is_deeply([@{ids('track','gemeinsam')}[0..2]],[100,101,102],'stable ID tie break');

# Runtime adapter with real SQLite and tiny LMS API doubles.
BEGIN {
 $INC{'Slim/Utils/Prefs.pm'}=1; $INC{'Slim/Utils/Log.pm'}=1;
 $INC{'Slim/Utils/PluginManager.pm'}=1; $INC{'Slim/Utils/Scanner/API.pm'}=1;
 package Slim::Utils::Prefs;
 sub import { no strict 'refs'; *{caller().'::preferences'}=sub {bless {},'MockPrefs'}; }
 package MockPrefs;
 our %values;
 sub init {my($s,$v)=@_; %values=(%$v,%values)}
 sub get {$values{$_[1]}}
 sub set {$values{$_[1]}=$_[2]}
 package Slim::Utils::Log; sub addLogCategory {bless {},'MockLog'}
 package MockLog; sub warn {}
 package Slim::Utils::PluginManager; sub isEnabled {1}
 package Slim::Utils::Scanner::API; our $AUTOLOAD; sub AUTOLOAD {} sub DESTROY {}
 package Slim::Music::Import; sub stillScanning {0}
 package Slim::Control::Request; sub subscribe {} sub addDispatch {}
 package Slim::Control::Queries; our $clears=0; sub wipeCaches {$clears++}
 package Slim::Plugin::FullTextSearch::Plugin;
 our $called=0; sub createHelperTable {$called++}
 package main; sub WEBUI () {0}
}
our $VERSION='9.0.3';
{no warnings 'once'; *Slim::Schema::dbh=sub {$db};}
require Plugins::SearchFocus::Plugin;
Plugins::SearchFocus::Plugin->initPlugin;
Plugins::SearchFocus::Plugin->postinitPlugin;
ok(Plugins::SearchFocus::Plugin::state()->{hook},'hook installed');
is($Slim::Control::Queries::clears,1,'activation clears LMS query counts');
Plugins::SearchFocus::Plugin::configurationChanged();
is($Slim::Control::Queries::clears,2,'preference update clears LMS query counts');
Slim::Plugin::FullTextSearch::Plugin->createHelperTable({name=>'tracksSearch',type=>'track',search=>'gemeinsam'});
is($db->selectrow_array('SELECT count(*) FROM tracksSearch'),601,'adapter inserts complete set');
is_deeply($db->selectcol_arrayref('SELECT id FROM tracksSearch ORDER BY fulltextweight DESC LIMIT 3 OFFSET 1'),[101,102,103],'pagination stable');
is($db->selectrow_array('SELECT count(*) FROM tracksSearch WHERE id BETWEEN 200 AND 299'),100,'filters apply before count');
$MockPrefs::values{enabled}=0;
Slim::Plugin::FullTextSearch::Plugin->createHelperTable({name=>'tracksSearch',type=>'track',search=>'lyrics'});
is($Slim::Plugin::FullTextSearch::Plugin::called,1,'original mode delegates');
$MockPrefs::values{enabled}=1;
Slim::Plugin::FullTextSearch::Plugin->createHelperTable({name=>'tracksSearch',type=>'track',search=>'a'x257});
is($db->selectrow_array('SELECT count(*) FROM tracksSearch'),0,'invalid query fails closed');
ok(Plugins::SearchFocus::Plugin::state()->{error},'error exposed');
Plugins::SearchFocus::Plugin::clearCache();
my $before=Plugins::SearchFocus::Plugin->runSearch('track','Neuaufnahme');
is(scalar @{$before->{rows}},0,'initially no new track');
$db->do('INSERT INTO tracks VALUES (999,?,2,?)',undef,'Neuaufnahme','');
indexrow(999,'track','neuaufnahme','ferien','','');
Plugins::SearchFocus::Plugin::clearCache();
my $after=Plugins::SearchFocus::Plugin->runSearch('track','Neuaufnahme');
is_deeply([map {$_->{id}} @{$after->{rows}}],[999],'scan notification invalidation exposes new track');
$MockPrefs::values{title}=0;
Plugins::SearchFocus::Plugin::clearCache();
is(scalar @{Plugins::SearchFocus::Plugin->runSearch('track','Neuaufnahme')->{rows}},0,'preference update changes results');
$MockPrefs::values{title}=1;
$db->do('INSERT INTO contributors VALUES (10,?),(11,?)',undef,'Fryderyk Chopin','Frédéric Chopin');
Plugins::SearchFocus::Plugin::configurationChanged();
Slim::Plugin::FullTextSearch::Plugin->createHelperTable({name=>'artistsSearch',type=>'contributor',search=>'f. Chonpin'});
is_deeply($db->selectcol_arrayref('SELECT id FROM artistsSearch ORDER BY id'),[10,11],'artist adapter discovers names absent from FTS candidates');
Slim::Plugin::FullTextSearch::Plugin->createHelperTable({name=>'quickSearch',type=>'contributor',search=>'f. Chonpin'});
is_deeply($db->selectcol_arrayref('SELECT id FROM quickSearch ORDER BY id'),[10,11],'general-search contributor adapter discovers typo names');
is($db->selectrow_array('SELECT count(*) FROM quickSearch WHERE id=11'),1,'LMS filters can restrict name candidate table');
$MockPrefs::values{name_fuzzy}=0;
is(scalar @{Plugins::SearchFocus::Plugin->runSearch('contributor','f. Chonpin')->{rows}},0,'name switch restores previous candidate search');
$MockPrefs::values{name_fuzzy}=1;
$MockPrefs::values{artist}=0;
is(scalar @{Plugins::SearchFocus::Plugin->runSearch('contributor','f. Chonpin')->{rows}},0,'disabled artist field remains disabled');
$MockPrefs::values{artist}=1;
Plugins::SearchFocus::Plugin->shutdownPlugin;
Slim::Plugin::FullTextSearch::Plugin->createHelperTable({});
is($Slim::Plugin::FullTextSearch::Plugin::called,2,'shutdown restores original function');
ok(!Plugins::SearchFocus::Plugin::state()->{hook},'hook disabled');
is($Slim::Control::Queries::clears,4,'shutdown clears LMS query counts');
{
 package Slim::Web::Settings; sub new {bless {},shift} sub handler {return $_[2]}
}
$INC{'Slim/Web/Settings.pm'}=1;
require Plugins::SearchFocus::Settings;
$db->do('INSERT INTO genres VALUES (2,?),(3,?)',undef,'Klassik','Klassik-Jazz');
my $preview={testQuery=>'classic',testSearch=>1};
Plugins::SearchFocus::Settings->beforeRender($preview);
ok(!$preview->{testError},'settings preview runs including genre branch');
is($preview->{testGroups}[0]{name},'Genres','genre preview shown first');
is($preview->{testGroups}[0]{rows}[0]{label},'Klassik','genre preview uses spelling variants');
is($preview->{testGroups}[0]{total},1,'genre preview applies mixed exclusion');
my $bad={saveSettings=>1,pref_name_aliases=>'broken',pref_enabled=>0};
my $oldEnabled=$MockPrefs::values{enabled};
Plugins::SearchFocus::Settings->handler(undef,$bad);
ok($bad->{settingsError},'invalid alias settings visibly rejected');
is($MockPrefs::values{enabled},$oldEnabled,'invalid alias validation prevents partial settings save');
Plugins::SearchFocus::Settings->beforeRender($bad);
is($bad->{nameAliasesValue},'broken','invalid input retained for correction');
my $aliasText="Fryderyk Chopin | Chopin | Frederik Chopin";
my $good={saveSettings=>1,pref_name_aliases=>$aliasText,pref_name_fuzzy=>1,pref_enabled=>1,pref_artist=>1};
Plugins::SearchFocus::Settings->handler(undef,$good);
is($MockPrefs::values{name_aliases},$aliasText,'alias text saved as text not boolean');
is($MockPrefs::values{name_fuzzy},1,'name switch saved');
Plugins::SearchFocus::Settings->handler(undef,{saveSettings=>1,pref_enabled=>1});
is($MockPrefs::values{name_aliases},$aliasText,'cached old forms do not erase aliases');
done_testing;
