package Plugins::LyricTranslator::Backend;
use strict;
use warnings;
use utf8;
use File::Spec;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use JSON::XS;
use Digest::SHA1 qw(sha1_hex);
use Encode qw(encode);
use Time::HiRes qw(time);
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;
use Slim::Utils::Timers;
use Plugins::LyricTranslator::I18N qw(loc pair route catalog languageName);

my ($setup, $setupStarted, $active);
my (@queue, %pending);
my (@downloads, %downloadAttempt);
my $sequence = 0;
sub root { File::Spec->catdir(scalar Slim::Utils::OSDetect::dirsFor('prefs'), 'LyricTranslator') }
sub helper { File::Spec->rel2abs(File::Spec->catfile(dirname(__FILE__), 'helper', @_)) }
sub path { File::Spec->catfile(root(), @_) }
sub readJSON {
    my ($file) = @_;
    return unless -f $file;
    open my $fh, '<:raw', $file or die "Cannot read file: $!";
    local $/; my $data = <$fh>; close $fh;
    return decode_json($data);
}
sub writeJSON {
    my ($file, $data) = @_;
    my $tmp = $file . '.tmp';
    open my $fh, '>:raw', $tmp or die "Cannot write file: $!";
    print {$fh} encode_json($data) or die "Write failed: $!";
    close $fh or die "Close failed: $!";
    rename $tmp, $file or die "Save failed: $!";
}
sub modelReady {
    my ($key)=@_;
    my $base=path('models',$key);
    my $marker=eval {readJSON(File::Spec->catfile($base,'ready.json'))};
    if (!$marker && $key eq 'en-de') { $base=path('model'); $marker=eval {readJSON(path('ready.json'))}; }
    return $marker && ($marker->{model_sha256}||'') eq catalog()->{models}{$key}{sha256}
        && -f File::Spec->catfile($base,'model','model.bin') && -f File::Spec->catfile($base,'sentencepiece.model');
}
sub status {
    my ($source,$target)=@_; ($source,$target)=pair() unless defined $source;
    my $keys=route($source,$target);
    my $detected=preferences('plugin.lyrictranslator')->get('lastDetectedSource') || '';
    if ($source eq 'auto') {
        my $effective=exists(catalog()->{languages}{$detected}) ? $detected : 'en';
        $keys=route($effective,$target) if $effective ne $target;
    }
    my $state = eval { readJSON(path('setup-status.json')) } || {state=>'missing',code=>'missing'};
    # Legacy status text was persisted in German. Always render status anew.
    $state->{code} ||= $state->{state} eq 'ready' ? 'ready' : $state->{state} eq 'error' ? 'setup_error' : 'missing';
    if ($setup && $setup->alive) {
        $state->{state} = 'running';
    } elsif ($state->{state} eq 'running') {
        $state = {state=>'error',code=>'interrupted'};
    }
    $state->{ready} = -f path('runtime','python.exe') && !(grep {!modelReady($_)} @$keys) ? 1 : 0;
    $state->{runtime_ready}= -f path('runtime-ready.json') && -f path('runtime','Lib','site-packages','py3langid','langid.py') ? 1 : 0;
    $state->{ready}=0 if $source eq 'auto' && !$state->{runtime_ready};
    if ($state->{state} ne 'running' && $state->{state} ne 'error') {
        $state->{state}=$state->{ready} ? 'ready' : 'missing';
        $state->{code}=$state->{state};
    }
    $state->{message}=loc($state->{code});
    $state->{message}.=' '.$state->{detail} if $state->{detail};
    $state->{setup_source}=delete $state->{source} if $state->{source};
    $state->{setup_target}=delete $state->{target} if $state->{target};
    $state->{source}=$source; $state->{target}=$target;
    $state->{source_name}=languageName($source); $state->{target_name}=languageName($target);
    $state->{detected_name}=languageName($detected) if $source eq 'auto' && exists catalog()->{languages}{$detected};
    $state->{via}=@$keys>1 ? 'en' : '';
    $state->{supported} = $^O eq 'MSWin32' ? 1 : 0;
    $state->{folder} = root();
    $state->{busy} = $active ? 1 : 0;
    $state->{auto_download}=preferences('plugin.lyrictranslator')->get('autoDownload') ? 1 : 0;
    $state->{available_sources}=[map {{code=>$_,name=>languageName($_)}} grep {
        my $s=$_; $s ne $target && -f path('runtime','python.exe') && !(grep {!modelReady($_)} @{route($s,$target)})
    } sort keys %{catalog()->{languages}}];
    return $state;
}
sub startSetup {
    my ($source,$target)=@_; ($source,$target)=pair() unless defined $source; route($source,$target);
    die loc('windows') unless $^O eq 'MSWin32';
    return if $setup && $setup->alive;
    die loc('busy') if $active || @queue;
    make_path(root());
    writeJSON(path('setup-status.json'), {state=>'running',code=>'starting',source=>$source,target=>$target});
    require Proc::Background;
    my $powershell = File::Spec->catfile($ENV{SystemRoot} || 'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe');
    my $detected=preferences('plugin.lyrictranslator')->get('lastDetectedSource') || 'none';
    $detected='none' unless exists catalog()->{languages}{$detected};
    $setup = Proc::Background->new({die_upon_destroy=>1}, $powershell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',helper('setup.ps1'),'-Root',root(),'-Source',$source,'-Target',$target,'-DetectedSource',$detected);
    die loc('start_failed') unless $setup;
    $setupStarted = time();
    Slim::Utils::Timers::setTimer(__PACKAGE__, time()+1, \&pollSetup);
}
sub pollSetup {
    return unless $setup;
    if ($setup->alive && time()-$setupStarted < 1800) {
        Slim::Utils::Timers::setTimer(__PACKAGE__, time()+1, \&pollSetup);
        return;
    }
    if ($setup->alive) {
        $setup->die;
        writeJSON(path('setup-status.json'), {state=>'error',code=>'setup_timeout'});
    }
    $setup->wait; undef $setup;
    startNext();
}
sub requestDownload {
    my ($source,$target)=@_;
    return unless preferences('plugin.lyrictranslator')->get('autoDownload');
    return unless $source && $source ne 'auto' && $source ne $target;
    return unless eval {route($source,$target);1};
    my $key="$source-$target";
    return 1 if grep {$_->[0] eq $source && $_->[1] eq $target} @downloads;
    return if $downloadAttempt{$key} && time()-$downloadAttempt{$key}<600;
    return if @downloads>=8;
    $downloadAttempt{$key}=time();
    push @downloads,[$source,$target];
    return 1;
}
sub downloadResult {
    return {state=>'error',error_code=>'model_downloading',error=>loc('model_downloading'),retry_after=>60};
}
sub setLanguages {
    my ($source,$target)=@_;
    route($source,$target);
    my ($oldSource,$oldTarget)=pair();
    return if $source eq $oldSource && $target eq $oldTarget;
    die loc('busy') if ($setup && $setup->alive) || $active || @queue;
    my $prefs=preferences('plugin.lyrictranslator');
    $prefs->set('sourceLanguage',$source); $prefs->set('targetLanguage',$target);
}
sub translate {
    my ($text, $callback, $options) = @_;
    $options ||= {};
    my ($source,$target)=pair();
    $source=$options->{source} if defined $options->{source};
    $target=$options->{target} if defined $options->{target};
    eval {route($source,$target);1} or return $callback->({state=>'error',error=>"$@"});
    unless (defined($text) && length($text) && length($text)<=60000) {
        return $callback->({state=>'error', error=>loc('invalid_text')});
    }
    my $state = status($source,$target);
    return $callback->(downloadResult()) if $state->{state} eq 'running';
    unless (($source eq 'auto' ? $state->{runtime_ready} : $state->{ready}) && $state->{state} ne 'running') {
        if (requestDownload($source,$target)) { startNext(); return $callback->(downloadResult()); }
        return $callback->({state=>'error', error=>loc('need_setup')});
    }
    my $key = sha1_hex(encode('UTF-8',join("\0",$source,$target,$text)));
    if ($pending{$key}) { push @{$pending{$key}{callbacks}}, $callback; return; }
    if (keys(%pending) >= 8) { return $callback->({state=>'error', error=>loc('overloaded')}); }
    my $job = {key=>$key, text=>$text, source=>$source,target=>$target,callbacks=>[$callback]};
    $pending{$key} = $job;
    push @queue, $job;
    startNext();
}
sub startNext {
    return if $setup && $setup->alive;
    if (!$active && !@queue && @downloads) {
        my $pair=shift @downloads;
        eval {startSetup(@$pair);1} or writeJSON(path('setup-status.json'),{state=>'error',code=>'setup_error',detail=>"$@"});
        return;
    }
    return if $active || !@queue;
    $active = shift @queue;
    my $id = join('-', time(), $$, ++$sequence);
    $active->{input} = path('jobs', $id.'.request.json');
    $active->{output} = path('jobs', $id.'.response.json');
    $active->{started} = time();
    eval {
        make_path(path('jobs'));
        writeJSON($active->{input}, {source=>$active->{source}, target=>$active->{target}, text=>$active->{text}});
        require Proc::Background;
        $active->{process} = Proc::Background->new({die_upon_destroy=>1},path('runtime','python.exe'),helper('worker.py'),'--root',root(),'--request',$active->{input},'--response',$active->{output});
        die loc('start_failed') unless $active->{process};
        1;
    } or return finish({state=>'error', error=>"$@"});
    Slim::Utils::Timers::setTimer(__PACKAGE__, time()+0.25, \&poll);
}
sub poll {
    return unless $active;
    my $process = $active->{process};
    if ($process->alive && time()-$active->{started}<180) {
        Slim::Utils::Timers::setTimer(__PACKAGE__, time()+0.25, \&poll);
        return;
    }
    if ($process->alive) {
        $process->die;
        return finish({state=>'error',error=>loc('translation_timeout')});
    }
    my $exit = $process->wait;
    my $result = eval { readJSON($active->{output}) };
    $result = {state=>'error',error=>loc('invalid_result')} unless ref($result) eq 'HASH';
    $result = {state=>'error',error=>loc('process_error')} if $exit && ($result->{state}||'') eq 'ok';
    if ($result->{error_code}) { $result->{error}=loc($result->{error_code}); $result->{error}.=' '.$result->{detail} if $result->{detail}; }
    finish($result);
}
sub finish {
    my ($result) = @_;
    my $job = $active;
    if ($job->{source} eq 'auto' && $result->{detected} && exists(catalog()->{languages}{$result->{source}||''})) {
        my ($source,$target)=pair();
        preferences('plugin.lyrictranslator')->set('lastDetectedSource',$result->{source}) if $source eq 'auto' && $target eq $job->{target};
    }
    if (($result->{error_code}||'') eq 'need_setup' && $result->{source}) {
        $result->{error}=loc('need_setup').' ('.languageName($result->{source}).' → '.languageName($result->{target}).')';
    }
    undef $active;
    if (($result->{error_code}||'') eq 'need_setup' && requestDownload($result->{source},$result->{target})) {
        $result={%$result,%{downloadResult()}};
    }
    delete $pending{$job->{key}};
    unlink grep {defined && -f} ($job->{input}, $job->{output});
    for my $callback (@{$job->{callbacks}}) { eval { $callback->($result) }; }
    startNext();
}
sub shutdown {
    Slim::Utils::Timers::killTimers(__PACKAGE__);
    $setup->die if $setup && $setup->alive;
    $active->{process}->die if $active && $active->{process} && $active->{process}->alive;
    @queue = (); @downloads=(); %downloadAttempt=(); %pending = (); undef $active; undef $setup;
}
1;
