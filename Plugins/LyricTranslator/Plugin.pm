package Plugins::LyricTranslator::Plugin;
use strict;
use warnings;
use utf8;
use base qw(Slim::Plugin::Base);
use Scalar::Util qw(blessed);
use Slim::Control::Request;
use Slim::Menu::TrackInfo;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Timers;
use Time::HiRes qw(time);
use Plugins::LyricTranslator::Backend;
use Plugins::LyricTranslator::I18N qw(loc pair route catalog languageName);

our $VERSION = '0.3.0';
my $prefs = preferences('plugin.lyrictranslator');
sub getDisplayName { 'PLUGIN_LYRICTRANSLATOR' }
sub initPlugin {
    my $class = shift;
    $class->SUPER::initPlugin(@_);
    $prefs->init({showOriginal=>1,autoDownload=>1,sourceLanguage=>'en',targetLanguage=>'de'});
    Slim::Control::Request::addDispatch(['lyrictranslator','lyrics'],[0,1,1,\&lyricsQuery]);
    Slim::Control::Request::addDispatch(['lyrictranslator','status'],[0,1,0,\&statusQuery]);
    Slim::Control::Request::addDispatch(['lyrictranslator','languages'],[0,1,0,\&languagesQuery]);
    Slim::Menu::TrackInfo->registerInfoProvider(lyrictranslator => (func=>\&trackInfo, after=>'moretrackinfo'));
    if (main::WEBUI) { require Plugins::LyricTranslator::Settings; Plugins::LyricTranslator::Settings->new; }
}
sub shutdownPlugin {
    Plugins::LyricTranslator::Backend::shutdown();
    Slim::Menu::TrackInfo->deregisterInfoProvider('lyrictranslator');
}
sub statusQuery {
    my ($request) = @_;
    my $state = Plugins::LyricTranslator::Backend::status();
    $state->{version}=$VERSION;
    $request->addResult($_,$state->{$_}) for keys %$state;
    $request->setStatusDone;
}
sub languagesQuery {
    my ($request)=@_;
    my $i=0;
    for my $code ('auto',sort {languageName($a) cmp languageName($b)} keys %{catalog()->{languages}}) {
        $request->addResultLoop('languages_loop',$i,'code',$code);
        $request->addResultLoop('languages_loop',$i,'name',languageName($code));
        $request->addResultLoop('languages_loop',$i,'source_only',$code eq 'auto' ? 1 : 0);
        $i++;
    }
    $request->addResult('count',$i);
    $request->setStatusDone;
}
sub trackInfo {
    my ($client,$url,$obj,$remote) = @_;
    my %args;
    $remote ||= {};
    if (blessed($obj) && $obj->isa('Slim::Schema::Track')) {
        $args{track_id}=$obj->id;
        $args{title}=$obj->title;
        $args{artist}=$obj->artistName;
    }
    $args{title} ||= $remote->{title};
    $args{artist} ||= $remote->{artist};
    $args{url} = $url if $url;
    return unless $args{track_id} || ($args{title} && $args{artist});
    my ($source,$target)=pair();
    return {name=>loc('menu',languageName($source),languageName($target)),type=>'link',url=>\&menuLyrics,passthrough=>[\%args]};
}
sub fetchLyrics {
    my ($client,$args,$callback) = @_;
    my $mode=defined($args->{mode}) ? $args->{mode} : 'translated';
    return $callback->({state=>'error',error=>loc('invalid_mode'),error_code=>'invalid_mode'}) unless $mode eq 'translated' || $mode eq 'original';
    my ($source,$target)=pair();
    $source=$args->{source} if defined $args->{source};
    $target=$args->{target} if defined $args->{target};
    if ($mode eq 'translated') {
        eval {route($source,$target);1} or return $callback->({state=>'error',error=>"$@"});
    }
    my @command = ('musicartistinfo','lyrics',($mode eq 'original' && !$args->{timestamps}) ? 'timestamps:0' : 'timestamps:1');
    for my $key (qw(track_id title artist album url duration)) {
        push @command, "$key:$args->{$key}" if defined($args->{$key}) && length($args->{$key});
    }
    my $finished = 0;
    my $received = 0;
    my $guard = {};
    my $finish = sub {
        return if $finished++;
        Slim::Utils::Timers::killTimers($guard);
        $callback->(@_);
    };
    my $got = sub {
        my ($request) = @_;
        return if $finished || $received++;
        Slim::Utils::Timers::killTimers($guard);
        my $original = $request->getResult('lyrics');
        my $error = $request->getResult('error');
        return $finish->({state=>'error',error=>$error || loc('no_lyrics')}) if $error || !defined($original) || $original !~ /\S/;
        my $title = $request->getResult('title') || $args->{title} || '';
        my $artist = $request->getResult('artist') || $args->{artist} || '';
        if ($mode eq 'original') {
            return $finish->({state=>'ok',mode=>'original',lyrics=>$original,plain=>$original,original=>$original,title=>$title,artist=>$artist,unchanged=>1});
        }
        Plugins::LyricTranslator::Backend::translate($original, sub {
            my ($result)=@_;
            $finish->({%$result, mode=>'translated',original=>$original, title=>$title, artist=>$artist});
        },{source=>$source,target=>$target});
    };
    Slim::Utils::Timers::setTimer($guard,time()+90,sub { $finish->({state=>'error',error=>loc('lookup_timeout')}); });
    my $request;
    eval { $request = Slim::Control::Request::executeRequest($client,\@command); 1 }
        or return $finish->({state=>'error',error=>loc('mai_missing')});
    return $finish->({state=>'error',error=>loc('mai_missing')}) unless $request;
    if ($request->isStatusProcessing) { $request->callbackFunction($got); }
    else { $got->($request); }
}
sub lyricsQuery {
    my ($request) = @_;
    if ($request->isNotQuery([['lyrictranslator'],['lyrics']])) { $request->setStatusBadDispatch; return; }
    my %args = map {$_=>$request->getParam($_)} qw(track_id title artist album url duration source target mode timestamps);
    $request->setStatusProcessing;
    fetchLyrics($request->client,\%args,sub {
        my ($result)=@_;
        if (($result->{state}||'') eq 'ok') {
            $request->addResult('lyrics',$request->getParam('timestamps') ? $result->{lyrics} : $result->{plain});
            $request->addResult($_,$result->{$_}) for grep {defined $result->{$_}} qw(original title artist source target cached via detected confidence unchanged mode);
            $request->addResult('translated',$result->{unchanged} ? 0 : 1);
        } else {
            $request->addResult('error',$result->{error} || loc('translation_error'));
            $request->addResult($_,$result->{$_}) for grep {defined $result->{$_}} qw(error_code source target detected confidence retry_after);
        }
        $request->setStatusDone;
    });
}
sub menuLyrics {
    my ($client,$cb,$params,$args) = @_;
    fetchLyrics($client,$args || {},sub {
        my ($result)=@_;
        my $text = $result->{error} || '';
        if (($result->{state}||'') eq 'ok') {
            $text = ($result->{unchanged} ? loc('already_target') : loc('translated',languageName($result->{source}),languageName($result->{target})))."\n\n".$result->{plain};
            if ($prefs->get('showOriginal')) {
                my $original = $result->{original};
                $original =~ s/\[(?:\d+:)?\d+:\d+(?:[.,]\d+)?\]//g;
                $text .= "\n\n".loc('original')."\n\n".$original unless $result->{unchanged};
            }
        }
        my $items = ($params && $params->{isButton})
            ? [map {{name=>$_,type=>'text'}} split(/\n/,$text)]
            : [{name=>$text,type=>'textarea'}];
        $cb->({items=>$items});
    });
}
1;
