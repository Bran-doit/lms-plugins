package Plugins::DBRepair::Plugin;
use strict;
use warnings;
use utf8;
use JSON::XS;
use File::Spec;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use Carp qw(longmess);
use POSIX qw(strftime);
use Cwd qw(abs_path);
use Slim::Utils::Prefs;
use Slim::Utils::Timers;
use Slim::Music::Import;
use Slim::Control::Request;
use Plugins::DBRepair::Trace;
use Time::HiRes ();

our $VERSION = '0.7.1';
my ($diagnostic,$diagnosticFile,$diagnosticStart);
my ($traceInitialized,$traceSetupError);
sub setTrace {
    my ($enabled)=@_;make_path(folder()) unless -d folder();
    if ($enabled) {writeNew('trace.enabled',{enabled=>1,time=>Time::HiRes::time()}) unless -f path('trace.enabled');}
    else {unlink path('trace.enabled') if -f path('trace.enabled');}
}
sub protectReport {
    my ($name,$reason)=@_;
    die "Ungueltige Pruef-ID" unless defined($name) && $name =~ /\Acheck-\d+-\d+\.json\z/ && -f path($name);
    writeNew($name.'.protected.json',{reason=>$reason||'manual',protected_epoch=>Time::HiRes::time()}) unless -f path($name.'.protected.json');
}
sub retainReports {
    opendir(my $dh,folder()) or return;my @files=sort {$b cmp $a} grep {/\Acheck-\d+-\d+\.json\z/} readdir $dh;closedir $dh;
    my @unprotected=grep {!-f path($_.'.protected.json')} @files;
    if (@unprotected>20) {for my $file (@unprotected[20..$#unprotected]) {unlink path($file),path($file.'.context.json'),path($file.'.end.json'),path($file.'.trace.json');}}
}
sub ensureReferences {
    opendir(my $dh,folder()) or return;
    my @files=sort grep {/\Acheck-\d+-\d+\.json\z/} readdir $dh;closedir $dh;
    my %seen;
    for my $file (@files) {my $p=eval {readJSON($file.'.protected.json')};$seen{$p->{reason}}=1 if $p && $p->{reason};}
    for my $file (@files) {
        my $r=eval {readJSON($file)};next unless $r && ($r->{mode}||'') ne 'trace';
        my $reason=$r->{state} eq 'ok'?'reference_healthy':'first_failure';
        unless ($seen{$reason}) {protectReport($file,$reason);$seen{$reason}=1;}
    }
}
sub finalizeEvidence {
    my ($name)=@_;my $r=readJSON($name);
    my %protectedReason;
    opendir(my $dh,folder()) or return;
    for my $file (grep {/\Acheck-\d+-\d+\.json\.protected\.json\z/} readdir $dh) {my $p=eval {readJSON($file)};$protectedReason{$p->{reason}}=1 if $p && $p->{reason};}closedir $dh;
    my $reason=$r->{state} eq 'ok'?'reference_healthy':'first_failure';
    protectReport($name,$reason) unless $protectedReason{$reason};
    my $end=Time::HiRes::time();
    my $timeline=Plugins::DBRepair::Trace::timeline(folder(),$diagnosticStart-300,$end);
    $timeline->{check_interval}={from=>$diagnosticStart,to=>$end,context_preceding_seconds=>300};
    $timeline->{overlapping_check_operation_ids}=[map {$_->{operation_id}} grep {defined($_->{end_timestamp}) && $_->{timestamp}<=$end && $_->{end_timestamp}>=$diagnosticStart} @{$timeline->{rebuild_intervals}}];
    $timeline->{enabled_at_finish}=Plugins::DBRepair::Trace::enabled();
    $timeline->{log_error}=Plugins::DBRepair::Trace::logging_error();
    writeNew($name.'.trace.json',$timeline) unless -f path($name.'.trace.json');
}
sub exportTrace {
    die "Ablaufbericht nicht aus aktiver Bibliotheksoperation erstellen" if Plugins::DBRepair::Trace::active();
    make_path(folder()) unless -d folder();
    my $stamp=time();my $name='check-'.$stamp.'-'.$$.int(rand(1000000)).'.json';
    my $timeline=Plugins::DBRepair::Trace::timeline(folder(),undef,Time::HiRes::time());
    writeNew($name,{schema_version=>4,check_id=>$name,mode=>'trace',state=>'observed',started=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime($stamp)),finished=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime()),messages=>['Beobachtungsprotokoll; keine Integritaetspruefung. Fehlende Ende-Ereignisse bleiben unvollstaendig.'],trace=>$timeline});
    writeNew($name.'.trace.json',$timeline);retainReports();
}
sub failedDiagnostic {
    my ($message,$exit)=@_;
    my $context=eval {readJSON($diagnosticFile.'.context.json')} || {};
    return {schema_version=>2,check_id=>$diagnosticFile,state=>'error',mode=>$context->{mode},label=>$context->{label},trigger=>'manual',started=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime($diagnosticStart)),finished=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime()),seconds=>time()-$diagnosticStart,output_complete=>0,database=>{path=>$context->{database_path},kind=>'original'},command=>($context->{mode}||'') eq 'compare' ? 'Integrity check and read-only comparison of both databases' : 'PRAGMA '.($context->{mode}||'unknown').'(2147483647)',server_start=>$context,messages=>[$message],error=>{category=>'process_error',code=>undef,process_exit_status=>$exit,message=>$message,stack=>longmess($message)}};
}
sub diagnosticContext {
    my $context={captured_epoch=>Time::HiRes::time(),server_pid=>$$,lms_version=>$::VERSION||'unknown',dbrepair_version=>$VERSION,scanner_pid=>undef,scanner_pid_note=>'Nicht durch diese LMS-Schnittstelle ermittelt',trace_enabled=>Plugins::DBRepair::Trace::enabled(),active_operation_ids=>Plugins::DBRepair::Trace::current_ids()};
    eval {$context->{scanning}=Slim::Music::Import->stillScanning ? 1 : 0;1} or $context->{scan_status_error}="$@";
    eval {
        my $scanner=Slim::Music::Import->scanningProcess;
        $context->{scanner_pid}=($scanner && $scanner->alive) ? $scanner->pid : undef;
        $context->{scanner_pid_note}=$context->{scanner_pid} ? 'LMS scanningProcess' : 'Kein aktiver von LMS verwalteter Scannerprozess';1;
    } or $context->{scanner_pid_note}="$@";
    eval {
        require Slim::Utils::PluginManager;
        my @plugins;
        for my $module (sort(Slim::Utils::PluginManager->enabledPlugins)) {
            my $data=Slim::Utils::PluginManager->dataForPlugin($module)||{};
            no strict 'refs';
            push @plugins,{module=>$module,version=>$data->{version}||${$module.'::VERSION'}||'unknown'};
        }
        $context->{enabled_plugins}=\@plugins;1;
    } or $context->{plugins_error}="$@";
    eval {
        my $dbh=Slim::Schema->dbh;
        $context->{sqlite_version}=$dbh->selectrow_array('SELECT sqlite_version()');
        for my $pragma (qw(journal_mode synchronous locking_mode busy_timeout)) {$context->{connection}{$pragma}=$dbh->selectrow_array("PRAGMA $pragma");}
        $context->{connection}{scope}='lms_connection';1;
    } or $context->{connection_error}="$@";
    return $context;
}
sub comparisonBackup {
    my ($id)=@_;
    die "Bitte eine gültige Sicherung auswählen" unless defined($id) && $id =~ /\A\d{8}T\d{6}-[a-f0-9]{8}\z/;
    my $catalog=readJSON('backups.json');
    die "Sicherung nicht im aktuellen Katalog" unless grep {$_->{id} eq $id} @{$catalog->{items}||[]};
    my $configPath=File::Spec->catfile($ENV{ProgramFiles}||'C:\\Program Files','DB Repair','config.json');
    open my $fh,'<:raw',$configPath or die "Helferkonfiguration für Sicherungspfad nicht lesbar: $configPath ($!).";
    local $/;my $config=decode_json(<$fh>);close $fh;
    die "Helferkonfiguration gehört zu einem anderen LMS-Cache" unless lc(File::Spec->canonpath($config->{CacheDir})) eq lc(File::Spec->canonpath(preferences('server')->get('cachedir')));
    my $root=abs_path($config->{BackupDir}) or die "Sicherungsordner nicht erreichbar";
    my $path=File::Spec->catfile($root,$id,'library.db');
    die "Sicherungsdatenbank fehlt oder ist nicht lesbar" unless -f $path && -r $path;
    return $path;
}
sub startDiagnostic {
    my ($mode,$label,$backupId)=@_;
    die "Unbekannte Prüfung" unless $mode =~ /\A(?:quick_check|integrity_check|compare)\z/;
    die "Pruefung nicht innerhalb einer aktiven Bibliotheksoperation starten" if Plugins::DBRepair::Trace::active();
    die "Ungültige Kennzeichnung" unless $label =~ /\A(?:manual|before_scan|after_scan|before_update|after_update)\z/;
    die "Ein Auftrag oder Scan läuft bereits" if state()->{queued} || Slim::Music::Import->stillScanning;
    die "Für die Diagnose ist ein Perl-Interpreter erforderlich" unless $^X =~ /perl(?:\.exe)?\z/i;
    my $backupPath=$mode eq 'compare' ? comparisonBackup($backupId) : undef;
    require Proc::Background;
    make_path(folder()) unless -d folder();
    my $script=File::Spec->rel2abs(File::Spec->catfile(dirname(__FILE__),'check.pl'));
    $diagnosticFile='check-'.time().'-'.$$.int(rand(1000000)).'.json';
    $diagnosticStart=Time::HiRes::time();
    my $database=File::Spec->catfile(preferences('server')->get('librarycachedir') || preferences('server')->get('cachedir'),'library.db');
    my $context=diagnosticContext();$context->{check_id}=$diagnosticFile;$context->{database_path}=$database;$context->{mode}=$mode;$context->{label}=$label;
    if ($backupPath) {$context->{backup_path}=$backupPath;$context->{backup_id}=$backupId;}
    writeNew($diagnosticFile.'.context.json',$context);
    $diagnostic=Proc::Background->new({die_upon_destroy=>1},$^X, (map {('-I',$_)} grep {!ref($_)} @INC), $script,$database,path($diagnosticFile),$mode,$label,path($diagnosticFile.'.context.json'));
    die "Diagnoseprozess konnte nicht gestartet werden" unless $diagnostic;
    Slim::Utils::Timers::setTimer(__PACKAGE__,time()+2,\&pollDiagnostic);
}
sub pollDiagnostic {
    return unless $diagnostic;
    if ($diagnostic->alive && time()-$diagnosticStart<630) {
        Slim::Utils::Timers::setTimer(__PACKAGE__,time()+2,\&pollDiagnostic);return;
    }
    $diagnostic->die if $diagnostic->alive;
    my $exit=$diagnostic->wait;
    undef $diagnostic;
    eval {writeNew($diagnosticFile.'.end.json',diagnosticContext())};
    unless (-f path($diagnosticFile)) {
        eval {writeNew($diagnosticFile,failedDiagnostic('Diagnose abgebrochen: Zeitlimit oder Prozessfehler. Kein erfolgreiches Prüfergebnis.',$exit))};
    }
    eval {finalizeEvidence($diagnosticFile);retainReports();};
}
sub folder { File::Spec->catdir(preferences('server')->get('cachedir'), 'dbrepair') }
sub path { File::Spec->catfile(folder(), $_[0]) }
sub readJSON {
    my ($name) = @_;
    return {} unless -f path($name);
    open my $fh, '<:raw', path($name) or die "DB Repair: $!";
    local $/; my $data = <$fh>; close $fh;
    return decode_json($data);
}
sub writeNew {
    my ($name, $value) = @_;
    sysopen(my $fh, path($name), O_WRONLY|O_CREAT|O_EXCL) or die "Auftrag bereits vorhanden oder Ordner nicht beschreibbar: $!\n";
    binmode $fh;
    print {$fh} encode_json($value) or die "Auftrag konnte nicht geschrieben werden: $!";
    close $fh or die "Auftrag konnte nicht geschlossen werden: $!";
}
sub preinitPlugin {
    return if $traceInitialized;
    eval {
        my $db=File::Spec->catfile(preferences('server')->get('librarycachedir')||preferences('server')->get('cachedir'),'library.db');
        Plugins::DBRepair::Trace::configure(folder(),$db,main::SCANNER?'scanner':'server');
        Plugins::DBRepair::Trace::install();$traceInitialized=1;1;
    } or do {$traceSetupError="$@";eval {Plugins::DBRepair::Trace::uninstall()};};
}
sub initPlugin {
    preinitPlugin();
    return if main::SCANNER;
    eval {ensureReferences()};
    Slim::Control::Request::subscribe(\&scanDone, [['rescan'], ['done']]);
    if (main::WEBUI) { require Plugins::DBRepair::Settings; Plugins::DBRepair::Settings->new; }
}
sub scanDone {
    return unless -e path('scan.running');
    eval { writeNew('scan.finished', {time=>time()}) };
}
sub state {
    my $data = eval { readJSON('status.json') } || {};
    my $heartbeat = eval { readJSON('heartbeat.json') } || {};
    $data->{ready} = ($heartbeat->{time} && time() - $heartbeat->{time} < 180) ? 1 : 0;
    $data->{restartSupported} = ($heartbeat->{version} || '') =~ /\A0\.(?:2|6|7)\.\d+\z/ ? 1 : 0;
    $data->{helperEvidenceSupported}=($heartbeat->{version}||'') =~ /\A0\.[67]\.0\z/?1:0;
    $data->{backupSupported}=($heartbeat->{version}||'') eq '0.7.0'?1:0;
    $data->{trace_enabled}=Plugins::DBRepair::Trace::enabled();
    $data->{trace_error}=$traceSetupError||Plugins::DBRepair::Trace::logging_error();
    $data->{queued} = -e path('request.json') || -e path('working.json') || -e path('scan.pending') || -e path('scan.running');
    $data->{queued}=1 if $diagnostic;
    $data->{diagnosing}=$diagnostic ? 1 : 0;
    my @reports;
    if (opendir(my $dh,folder())) {
        my @names=sort {$b cmp $a} grep {/\Acheck-\d+-\d+\.json\z/} readdir($dh);closedir $dh;
        for my $name (@names) {
            my $r=eval {readJSON($name)};
            if ($r) {
                $r->{check_id}||=$name;$r->{server_start}||=eval {readJSON($name.'.context.json')};$r->{server_finish}=eval {readJSON($name.'.end.json')};
                $r->{protection}=eval {readJSON($name.'.protected.json')};
                $r->{trace}=eval {readJSON($name.'.trace.json')};
                # Do not recompute historical evidence or rehash backups on every page load.
                $r->{details_json}=JSON::XS->new->canonical->pretty->encode($r);push @reports,$r;
            }
        }
    }
    $data->{checks}=\@reports;
    $data->{scanning} = eval { Slim::Music::Import->stillScanning } ? 1 : 0;
    $data->{backups} = (eval { readJSON('backups.json')->{items} }) || [];
    $data->{version} = $VERSION;
    return $data;
}
sub submit {
    my ($action, $id, $confirmation) = @_;
    die "Unbekannte Aktion.\n" unless $action =~ /\A(?:restart|reset|backup|delete)\z/;
    die "Aktion wurde nicht bestätigt.\n" unless $confirmation eq '1';
    my $s = state();
    die "Bitte Windows-Helfer auf Version 0.7.0 aktualisieren.\n" if $action eq 'backup' && !$s->{backupSupported};
    die "Windows-Helfer nicht erreichbar. Installation prüfen.\n" unless $s->{ready};
    die "Bitte Windows-Helfer auf Version 0.2.0 aktualisieren.\n" if $action eq 'restart' && !$s->{restartSupported};
    die "Ein Auftrag oder Scan läuft bereits.\n" if $s->{queued} || $s->{scanning};
    die "Ungültige Sicherung.\n" if $action eq 'delete' && (!defined($id) || $id !~ /\A[0-9]{8}T[0-9]{6}-[a-f0-9]{8}\z/);
    writeNew('request.json', {action=>$action, id=>$id || '', created=>time(),($action =~ /\A(?:reset|backup)\z/?(creation_context=>diagnosticContext()):())});
}
sub postinitPlugin {
    return if main::SCANNER;
    Slim::Utils::Timers::setTimer(__PACKAGE__, time()+10, \&resumeScan);
}
sub resumeScan {
    return unless -e path('scan.pending');
    if (Slim::Music::Import->stillScanning) {
        Slim::Utils::Timers::setTimer(__PACKAGE__, time()+10, \&resumeScan);
        return;
    }
    # Rename first: never repeatedly issue a full scan after a crash/restart.
    return unless rename(path('scan.pending'), path('scan.running'));
    my $ok = eval {
        my $request = Slim::Control::Request::executeRequest(undef, ['rescan']);
        die "LMS hat den Scan abgelehnt" unless $request && !$request->isStatusError;
        1;
    };
    if (!$ok) {
        eval { writeNew('scan.failed', {message=>"$@"}) };
    }
}
sub shutdownPlugin {
    if ($diagnostic) {
        $diagnostic->die; undef $diagnostic;
        eval {writeNew($diagnosticFile,failedDiagnostic('Prüfung durch LMS-Beendigung abgebrochen.',undef))} unless -f path($diagnosticFile);
    }
    Slim::Utils::Timers::killTimers(__PACKAGE__, \&pollDiagnostic) unless main::SCANNER;
    Slim::Control::Request::unsubscribe(\&scanDone) unless main::SCANNER;
    Slim::Utils::Timers::killTimers(__PACKAGE__, \&resumeScan) unless main::SCANNER;
    Plugins::DBRepair::Trace::uninstall();
    $traceInitialized=0;
}
1;


