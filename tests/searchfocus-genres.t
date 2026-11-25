use strict; use warnings; use utf8; use Test::More;
use lib '.';
use Plugins::SearchFocus::I18N ();
BEGIN { $Plugins::SearchFocus::I18N::LANGUAGE='de'; }
use Plugins::SearchFocus::Genres;
my @rows=map {{id=>$_->[0],genre=>$_->[1]}} ([1,'Klassik'],[2,'Klassik-Jazz'],[3,'Jazz-Klassik'],[4,'Jazz'],[5,'Heavy Metal']);
sub scored { Plugins::SearchFocus::Genres::score(@_) }
sub ranked { [map {$_->{id}} @{Plugins::SearchFocus::Genres::rank(\@rows,@_)}] }
is(scored('Klassik','classic',1)->{score},1000,'spelling variant exact');
is(scored('Klassik','klassic',1)->{score},1000,'klassic variant exact');
is(scored('Klassik','klasik',1)->{score},600,'missing letter');
is(scored('Klassik','classc',1)->{score},600,'typo in alternative spelling');
is(scored('Classic','classik',1)->{score},600,'substitution in alternative spelling');
is(scored('Klassik','klazsikk',1),undef,'two changes excluded');
is(scored('Klassik','klassisik',1),undef,'multiple insertions excluded');
is(scored('Jazz','jazx',1)->{score},600,'one replacement');
is(scored('Jazz','jazzx',1)->{score},600,'one extra letter');
is(scored('Klassik','klasis k',1),undef,'query words cannot share one result word');
is(scored('Klassik','klasis k',0),undef,'same with mixed allowed');
is(scored('Klassik','klasski',1)->{score},600,'transposition');
is(scored('Jazz','jaz',1)->{score},800,'prefix search retained');
ok(!scored('Pop','pob',1),'short words no fuzzy');
is(scored('Klassik-Jazz','classic',0)->{score},800,'first component');
is(scored('Jazz-Klassik','classic',0)->{score},400,'second component');
is(scored('Klassik-Jazz','klasik',0)->{score},480,'first component fuzzy');
is(scored('Jazz-Klassik','klasik',0)->{score},240,'second component fuzzy');
is_deeply(ranked('classic',1),[1],'hide mixed by default');
is_deeply(ranked('classic',0),[1,2,3],'ordered pure first then first then secondary');
is_deeply(ranked('classic jazz',1),[2,3],'explicit compound regardless order');
is(scored('Klassik-Jazz','klasik jazz',1)->{score},800,'partial fuzzy compound');
for my $sep ('-','+','/','&','–') {ok(scored("Klassik${sep}Jazz",'classic jazz',1),'compound separator targeted'); ok(!scored("Klassik${sep}Jazz",'classic',1),'mixed filtered');}
ok(scored('Heavy Metal','heavy metal',1),'multiword genre not automatically a mixture');
my $spaced=[{id=>1,genre=>'Klassik'},{id=>2,genre=>'Classic Rock'},{id=>3,genre=>'Heavy Metal'}];
is_deeply([map {$_->{id}} @{Plugins::SearchFocus::Genres::rank($spaced,'classic',1)}],[1],'classic rock hidden with known components');
is_deeply([map {$_->{id}} @{Plugins::SearchFocus::Genres::rank($spaced,'classic rock',1)}],[2],'classic rock explicitly accessible');
is_deeply([map {$_->{id}} @{Plugins::SearchFocus::Genres::rank([$spaced->[1]],'classic',1)}],[],'component classification independent of library filters');
ok(!scored('Klassik','x'x257,1),'length limit');
ok(!scored('Klassik','',1),'empty safe');

# Request adapter tests: original LMS callbacks supply filtered rows.
{
 package Slim::Control::Request;
 our %dispatch; our @rows; our @calls;
 sub addDispatch {my($keys,$info)=@_; my $old=$dispatch{$keys->[0]}; $dispatch{$keys->[0]}=$info->[3]; return $old;}
 sub new {my($class,$client,$args)=@_;bless {client=>$client,params=>{_index=>$args->[1],_quantity=>$args->[2]},results=>{}},$class}
 sub getParam {$_[0]{params}{$_[1]}} sub addParam {$_[0]{params}{$_[1]}=$_[2]}
 sub getParamsCopy {return +{%{$_[0]{params}}}} sub clientid {$_[0]{client}} sub client {$_[0]{client}}
 sub getResults {$_[0]{results}} sub getResult {$_[0]{results}{$_[1]}}
 sub addResult {$_[0]{results}{$_[1]}=$_[2]}
 sub addResultLoop {$_[0]{results}{$_[1]}[$_[2]]{$_[3]}=$_[4]}
 sub setStatusDone {$_[0]{done}=1}
 sub normalize {my($r,$from,$num,$count)=@_; return (0,0,0) unless $count && $num && $from<$count; $from=0 if $from<0; my $end=$from+$num-1; $end=$count-1 if $end>=$count;return(1,$from,$end)}
 package Slim::Music::VirtualLibraries;
 sub getRealId {$_[1]} sub getLibraryIdForClient {$_[1] ? 42 : undef}
 package Slim::Utils::Text;
 sub matchCase {lc $_[0]}
}
my $originalGenres=sub {
 my $r=shift; push @Slim::Control::Request::calls,$r->getParamsCopy;
 my @filtered=@rows;
 @filtered=grep {$_->{id}==2} @filtered if $r->getParam('library_id') || $r->getParam('artist_id');
 @filtered=grep {$_->{id}==$r->getParam('genre_id')} @filtered if defined $r->getParam('genre_id');
 @filtered=grep {index(lc($_->{genre}),lc($r->getParam('search')))>=0} @filtered if $r->getParam('search');
 $r->addResult('count',scalar @filtered); $r->addResult('rescan',1);
 $r->addResult('genres_loop',[map {{%$_,textkey=>substr($_->{genre},0,1),favorites_url=>'db:genre'}} @filtered]); $r->setStatusDone;
};
my $originalSearch=sub {my $r=shift; my $old=($r->getParam('term')||'') eq 'klassik'?1:0; $r->addResult('genres_count',$old) if $old && !$r->getParam('_index'); $r->addResult('tracks_count',7);$r->addResult('tracks_loop',[{track=>'unchanged'}]);$r->addResult('count',7+$old);$r->setStatusDone};
$Slim::Control::Request::dispatch{genres}=$originalGenres;
$Slim::Control::Request::dispatch{search}=$originalSearch;
my %config=(enabled=>1,genre_fuzzy=>1,genre_hide_mixed=>0);
Plugins::SearchFocus::Genres::install(sub {\%config});
ok(Plugins::SearchFocus::Genres::installed(),'installed');
sub request {my($command,$index,$quantity,%params)=@_;my $r=Slim::Control::Request->new(undef,[$command,$index,$quantity]);$r->addParam($_,$params{$_}) for keys %params; $Slim::Control::Request::dispatch{$command}->($r);return $r->getResults;}
my $r=request('genres',1,1,search=>'classic',artist_id=>undef);
is($r->{count},3,'count before pagination');is($r->{genres_loop}[0]{id},2,'pagination after ranking');is(scalar @{$r->{genres_loop}},1,'page size');ok($r->{rescan},'scan status retained');
$r=request('genres',0,10,search=>'classic',artist_id=>99);is($r->{count},1,'original artist filter preserved');is($r->{genres_loop}[0]{id},2,'filtered result');
$r=request('genres',0,0,search=>'classic',tags=>'CC');is($r->{count},3,'count-only');ok(!exists$r->{genres_loop},'no count-only loop');
$r=request('genres',0,10,search=>'classic',tags=>'ZZ');ok($r->{indexList},'index available');ok(!exists$r->{genres_loop},'ZZ index only');
$config{genre_hide_mixed}=1;
$r=request('genres',0,10,genre_id=>2);is($r->{genres_loop}[0]{id},2,'direct genre access bypasses exclusion');
$r=request('genres',0,10);is($r->{count},5,'browse without query unchanged');
$r=request('search',0,10,term=>'classic');is($r->{genres_count},1,'global category replaced');is($r->{count},8,'global total updated');is($r->{tracks_loop}[0]{track},'unchanged','other categories retained');
$r=request('search',10,10,term=>'classic');is($r->{count},8,'total remains correct beyond genre page');ok(!exists$r->{genres_loop},'empty genre page');
$config{genre_hide_mixed}=0;
$r=request('search',10,10,term=>'klassik');is($r->{count},10,'original genre count subtracted even beyond page');
$config{genre_hide_mixed}=1;
$r=request('search',0,10,term=>'classic jazz',library_id=>42);is($r->{genres_count},1,'global library filter retained');
$config{genre_fuzzy}=0;$r=request('genres',0,10,search=>'classic');is($r->{count},0,'disabled delegates');
$config{genre_fuzzy}=1;$config{enabled}=0;$r=request('genres',0,10,search=>'classic');is($r->{count},0,'master switch delegates');
Plugins::SearchFocus::Genres::uninstall();is($Slim::Control::Request::dispatch{genres},$originalGenres,'genre callback restored');is($Slim::Control::Request::dispatch{search},$originalSearch,'global callback restored');
done_testing;
