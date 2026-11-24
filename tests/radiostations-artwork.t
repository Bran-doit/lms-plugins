use strict;use warnings;use Test::More;use lib '.';
BEGIN {
 $INC{'Slim/Utils/Cache.pm'}=__FILE__;
 package Slim::Utils::Cache;
 our %data;sub new {bless {},shift}sub get {$data{$_[1]}}sub set {$data{$_[1]}=$_[2]}
}
use Plugins::RadioStations::Artwork;
my $url='https://radio.test/live';my $logo='https://radio.test/logo.png';
Plugins::RadioStations::Artwork::remember($url,$logo);
is($Slim::Utils::Cache::data{'remote_image_'.$url},$logo,'missing cover receives logo');
is(Plugins::RadioStations::Artwork::logo($url),$logo,'station logo retained separately');
$Slim::Utils::Cache::data{'remote_image_'.$url}='https://covers.test/current.jpg';
Plugins::RadioStations::Artwork::remember($url,$logo);
is($Slim::Utils::Cache::data{'remote_image_'.$url},'https://covers.test/current.jpg','existing title cover wins');
delete $Slim::Utils::Cache::data{'remote_image_'.$url};
Plugins::RadioStations::Artwork::seed($url,Plugins::RadioStations::Artwork::logo($url));
is($Slim::Utils::Cache::data{'remote_image_'.$url},$logo,'expired cover falls back to stored logo');
$Slim::Utils::Cache::data{'remote_image_'.$url}='plugins/RadioStations/html/images/icon.png';
Plugins::RadioStations::Artwork::remember($url,$logo);
is($Slim::Utils::Cache::data{'remote_image_'.$url},$logo,'generic icon replaced by actual logo');
Plugins::RadioStations::Artwork::remember('https://bad.test','javascript:alert(1)');
ok(!Plugins::RadioStations::Artwork::logo('https://bad.test'),'invalid logo rejected');
Plugins::RadioStations::Artwork::remember('https://plain.test','plugins/RadioStations/html/images/icon.png');
ok(!Plugins::RadioStations::Artwork::logo('https://plain.test'),'generic plugin icon not treated as station logo');
{
 package TestTrack;sub url {$_[0]{url}}
 package TestSong;sub track {bless {url=>'https://radio.test/live'},'TestTrack'}sub currentTrack {bless {url=>'https://resolved.test/live'},'TestTrack'}
 package TestClient;sub playingSong {bless {},'TestSong'}
}
Plugins::RadioStations::Artwork::playing(bless {},'TestClient');
is($Slim::Utils::Cache::data{'remote_image_https://resolved.test/live'},$logo,'playlist logo propagated to resolved stream');
$Slim::Utils::Cache::data{'remote_image_https://resolved.test/live'}='https://covers.test/new.jpg';
Plugins::RadioStations::Artwork::playing(bless {},'TestClient');
is($Slim::Utils::Cache::data{'remote_image_https://resolved.test/live'},'https://covers.test/new.jpg','resolved stream title cover preserved');
Plugins::RadioStations::Artwork::playing(undef);
pass('no player is harmless');
ok(!exists $Slim::Utils::Cache::data{'remote_image_https://unrelated.test/live'},'unrelated streams untouched');
done_testing;
