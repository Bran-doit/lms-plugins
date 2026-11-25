use strict; use warnings; use utf8; use Test::More; use File::Temp qw(tempdir); use File::Path qw(make_path); use Template;
use lib '.';
BEGIN {
 $INC{'Slim/Utils/Prefs.pm'}=1;
 package Slim::Utils::Prefs; our $language='DE'; sub preferences {bless {},'ServerPrefs'}
 package ServerPrefs; sub get {return $Slim::Utils::Prefs::language}
}
use Plugins::SearchFocus::I18N qw(language loc);
use Plugins::SearchFocus::Engine;
use Plugins::SearchFocus::Names;
use Plugins::SearchFocus::Genres;
for my $case (['DE','de'],['de-DE','de'],['de_AT','de'],['EN','en'],['FR','en'],['NL','en'],['','en'],[undef,'en']) {
 $Slim::Utils::Prefs::language=$case->[0];is(language(),$case->[1],'server preference selects German or English fallback');
}
my $temp=tempdir(CLEANUP=>1);make_path("$temp/settings");
for my $file (qw(header footer)){open my $fh,'>',"$temp/settings/$file.html" or die $!;print $fh '';close $fh}
my $tt=Template->new({INCLUDE_PATH=>[$temp,'Plugins/SearchFocus/HTML/EN'],ENCODING=>'utf8'});
my %scores;my %controls;
for my $lang ('DE','EN','FR') {
 $Slim::Utils::Prefs::language=$lang;
 my $terms=Plugins::SearchFocus::Engine::tokens('meine freunde');
 my $rating=Plugins::SearchFocus::Engine::evaluate({artist=>'Deine Freunde'},$terms,'meine freunde','or');
 $scores{$lang}=$rating->{score};
 like($rating->{reason},$lang eq 'DE'?qr/Ähnlichkeit/:qr/Similarity/,'localized explanation');
 like($rating->{reason},qr/meine ≈ deine/,'query and metadata words not translated');
 my $out='';my $data={sfLanguage=>language(),focusState=>{version=>'0.6.0',fulltext=>0,supported=>1},focus=>{enabled=>1,mode=>'or',title=>1},nameAliasesValue=>'<script>user input</script>',testQuery=>'Chopin',testGroups=>[]};
 ok($tt->process('plugins/SearchFocus/settings/basic.html',$data,\$out),'template rendered') or diag $tt->error;
 like($out,qr/Search Focus/,'brand identical in both languages');
 unlike($out,qr/Suchfokus/,'old brand removed');
 like($out,qr/&lt;script&gt;user input&lt;\/script&gt;/,'stored text HTML escaped');
 like($out,$lang eq 'DE'?qr/Volltextsuche ist deaktiviert/:qr/Full Text Search is disabled/,'localized warning');
 like($out,$lang eq 'DE'?qr/Speichern und testen/:qr/Save and test/,'localized action');
 $controls{$lang}=[sort $out =~ /name="([^"]+)"/g];
 eval {Plugins::SearchFocus::Names::parseAliases('broken')};
 like($@,$lang eq 'DE'?qr/Namensvarianten/:qr/Name aliases/,'localized validation');
 eval {Plugins::SearchFocus::Engine::tokens('x'x257)};
 like($@,$lang eq 'DE'?qr/Suchbegriff/:qr/Search query/,'localized query error');
 my $names=Plugins::SearchFocus::Names::rank([{id=>1,name=>'Fryderyk Chopin'}],'f. Chonpin',\%Plugins::SearchFocus::Engine::DEFAULTS);
 like($names->[0]{reason},$lang eq 'DE'?qr/Initiale/:qr/initial/,'localized name explanation');
 is($names->[0]{label},'Fryderyk Chopin','library artist name preserved');
 my $genre=Plugins::SearchFocus::Genres::score('Klassik','classic',1);
 like($genre->{reason},$lang eq 'DE'?qr/Eigenständiges Genre/:qr/Standalone genre/,'localized genre explanation');
}
is($scores{DE},$scores{EN},'UI language does not affect score');
is($scores{EN},$scores{FR},'fallback score unchanged');
is_deeply($controls{DE},$controls{EN},'identical form controls in German and English');
is_deeply($controls{EN},$controls{FR},'fallback exposes identical controls');
done_testing;