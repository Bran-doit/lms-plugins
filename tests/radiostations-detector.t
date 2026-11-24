use strict;
use warnings;
use Test::More;
use HTTP::Headers;
use lib '.';
BEGIN {
    $INC{'Slim/Networking/SimpleAsyncHTTP.pm'}=__FILE__;
    package Slim::Networking::SimpleAsyncHTTP;
    our ($headers,$code,$fail,@requests);
    sub new {my ($class,$cb,$ecb,$options)=@_; bless {cb=>$cb,ecb=>$ecb,options=>$options},$class}
    sub head {my ($self,$url)=@_; push @requests,{url=>$url,options=>$self->{options}}; $fail ? $self->{ecb}->($self,'offline') : $self->{cb}->($self)}
    sub headers {$headers}
    sub code {$code}
}
use Plugins::RadioStations::Detector;
sub classify {
    my ($entry,$known,$rows)=@_;
    my ($result,@api);
    Plugins::RadioStations::Detector::classify($entry,$known||{},sub {push @api,$_[0]; $_[1]->($rows||[])},sub {$result=shift});
    return ($result,\@api);
}
$Slim::Networking::SimpleAsyncHTTP::code=200;
$Slim::Networking::SimpleAsyncHTTP::headers=HTTP::Headers->new('Content-Type'=>'audio/mpeg','icy-name'=>'Test radio','icy-metaint'=>16000);
my ($result,$api)=classify({url=>'https://example.org/live'});
is($result->{kind},'radio','audio plus station metadata and live delivery recognized');
is($result->{reason},'icy','ICY evidence reported');
is(scalar @$api,1,'public address checked in directory first');
is($Slim::Networking::SimpleAsyncHTTP::requests[-1]{options}{timeout},5,'HEAD timeout bounded');
$Slim::Networking::SimpleAsyncHTTP::headers->header('Content-Length'=>12345);
($result)=classify({url=>'https://example.org/recording.mp3'});
is($result->{kind},'unknown','finite audio with station headers not auto-moved');
$Slim::Networking::SimpleAsyncHTTP::headers=HTTP::Headers->new('Content-Type'=>'audio/mpeg');
($result)=classify({url=>'https://example.org/chunked'});
is($result->{kind},'unknown','missing duration or length alone is not radio evidence');
my $url='https://example.org/podcasts/episode.mp3';
($result,$api)=classify({url=>$url},{$url=>'uuid'},[{stationuuid=>'uuid',url=>$url}]);
is($result->{kind},'podcast','explicit podcast evidence overrides positive source');
is(scalar @$api,0,'podcast not probed');
($result)=classify({url=>'https://example.org/audio',parser=>'Podcasts'});
is($result->{kind},'podcast','parser origin respected');
($result)=classify({url=>'https://example.org/live'}, {}, [{stationuuid=>'uuid',url=>'https://example.org/live'}]);
is($result->{reason},'directory','exact directory match accepted');
($result)=classify({url=>'https://example.org/live'}, {}, [{stationuuid=>'uuid',url=>'https://different.org/live'}]);
is($result->{kind},'unknown','unrelated directory entry rejected');
($result)=classify({url=>'http://opml.radiotime.com/Tune.ashx?id=s123&formats=mp3'});
is($result->{reason},'tunein','TuneIn station ID recognized');
($result)=classify({url=>'http://opml.radiotime.com/Tune.ashx?id=p123&formats=mp3'});
is($result->{kind},'unknown','TuneIn nonstation ID not assumed radio');
for my $private ('http://192.168.1.2/live','http://localhost/live','http://radio.local/live','https://user:pass@example.org/live','https://example.org/live?token=secret') {
    ($result,$api)=classify({url=>$private});
    is(scalar @$api,0,'private/credential URL not sent to directory');
}
$Slim::Networking::SimpleAsyncHTTP::fail=1;
($result)=classify({url=>'https://example.org/offline'});
is($result->{kind},'unknown','network failure remains undecided');
($result)=classify({url=>'mms://example.org/live'});
is($result->{kind},'unknown','unsupported probe protocol remains manual');
done_testing;
