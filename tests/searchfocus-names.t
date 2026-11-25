use strict; use warnings; use utf8; use Test::More; use DBI; use lib '.';
use Plugins::SearchFocus::I18N ();
BEGIN { $Plugins::SearchFocus::I18N::LANGUAGE='de'; }
use Plugins::SearchFocus::Names;
my %config=%Plugins::SearchFocus::Engine::DEFAULTS;
my @rows=({id=>1,name=>'Fryderyk Chopin'},{id=>2,name=>'Frédéric Chopin'},{id=>3,name=>'Chopin'},
 {id=>4,name=>'Frederik Schubert'},{id=>5,name=>'Foo Fighters'},{id=>6,name=>'John Smith'},{id=>7,name=>'Jane Smith'},
 {id=>8,name=>'X'},{id=>9,name=>'Li'},{id=>10,name=>'Ludwig van Beethoven'},{id=>11,name=>'The National'});
sub rank { Plugins::SearchFocus::Names::rank(\@rows,$_[0],\%config) }
sub ids { [map {$_->{id}} @{rank($_[0])}] }
sub rate {my($name,$query,$aliases)=@_;my %c=(%config,name_aliases=>$aliases//'');return Plugins::SearchFocus::Names::rank([{id=>1,name=>$name}],$query,\%c)->[0]}
is_deeply(rank('Chopin'),rank('chopin'),'capitalization does not affect names');
is_deeply(ids('chopin'),[3,1,2],'exact standalone name before longer names');
for my $q ('Frederik Chopin','Frederyk Chopin','f. Chonpin','F Chopin') {
 is_deeply([sort {$a<=>$b} @{ids($q)}],[1,2,3],"spelling/initial finds all configured Chopin entries: $q");
}
is(ids('Fryderyk Chopin')->[0],1,'canonical full name beats aliases');
is(ids('Frédéric Chopin')->[0],2,'accented canonical name beats aliases');
is_deeply(ids('f.'),[],'initial alone does not enumerate names');
is_deeply(ids('z. Chopin'),[],'incorrect initial rejected in AND');
is_deeply(ids('f. Shonpin'),[],'two surname edits excluded');
is_deeply(ids('X'),[8],'one-letter artist exact still searchable');
is_deeply(ids('Lu'),[10],'two-letter prefix retained');
is_deeply(ids('Le'),[],'short name typo not expanded');
is_deeply(ids('f. Fighters'),[5],'group initials do not imply surname classification');
is_deeply([sort {$a<=>$b} @{ids('j. Smith')}],[6,7],'ambiguous initials keep separate people');
is_deeply(ids('Chopin Fryderyk'),[1,2,3],'name order independent');
is_deeply(ids('Fryderyk Fryderyk Chopin'),[1,2,3],'repeated query tokens deduplicated');
ok(!rate('John Smith','john j'),'same target word cannot satisfy two terms');
my $rules="Fryderyk Chopin | Chopin | Frederik Chopin";
cmp_ok(rate('Fryderyk Chopin','chopin',$rules)->{score},'>',rate('Fryderyk Chopin','fryderyk',$rules)->{score},'configured surname stronger than given name');
is(rate('Foo Fighters','foo')->{score},rate('Foo Fighters','fighters')->{score},'unconfigured band words equal');
my $multi="Ludwig van Beethoven | van Beethoven | Ludwig van Beethoven";
is_deeply([map {$_->{id}} @{Plugins::SearchFocus::Names::rank(\@rows,'l. van beethovn',{%config,name_aliases=>$multi})}],[10],'multiword surname and initial');
my $reverse="Chopin, Fryderyk | Chopin | Fryderyk Chopin";
ok(rate('Chopin, Fryderyk','f chonpin',$reverse),'surname first ordering supported');
my $r=rate('John Smith','john smtih');like($r->{reason},qr/Tippfehler/,'adjacent transposition explained');
$r=rate('John Smith','j smitth');like($r->{reason},qr/Initiale/,'initial explained');
$config{mode}='or';ok(rate('John Smith','john unknown'),'OR retains partial result');
ok(!rate('John Smith','j unknown'),'OR initial-only partial rejected');$config{mode}='and';
is_deeply(ids(''),[],'empty query');is_deeply(ids('???'),[],'punctuation');
eval {rank('x'x257)};like($@,qr/zu lang/,'query bound');
for my $bad ('Name only','Name | Wrong | Alias',"Name ||Alias\nname ||Other",'Name ||'.join(';',map {"alias $_"}1..13)) {
 eval {Plugins::SearchFocus::Names::parseAliases($bad)};ok($@,'invalid configuration rejected');
}
is_deeply(Plugins::SearchFocus::Names::parseAliases('# note'),{},'comments supported');
is_deeply(Plugins::SearchFocus::Names::rank([{id=>1,name=>'Other'}],'Frederik Chopin',\%config),[],'alias cannot create missing contributor');
my $db=DBI->connect('dbi:SQLite:dbname=:memory:','','',{RaiseError=>1,sqlite_unicode=>1});
$db->do('CREATE TABLE contributors(id INTEGER PRIMARY KEY,name TEXT)');
for my $row (@rows){$db->do('INSERT INTO contributors VALUES (?,?)',undef,$row->{id},$row->{name})}
my $result=Plugins::SearchFocus::Names->search($db,'f. Chonpin',\%config);
is_deeply([sort {$a<=>$b} map {$_->{id}} @{$result->{rows}}],[1,2,3],'real SQLite name directory finds typo-only candidates without FTS');
is($result->{candidates},scalar @rows,'all contributors considered');
# More than 500 candidates, deterministic tie breaking.
my @many=map {{id=>$_,name=>'John Smith'}} 1..650;
is(scalar @{Plugins::SearchFocus::Names::rank(\@many,'john smtih',\%config)},650,'no 500-result cutoff');
done_testing;