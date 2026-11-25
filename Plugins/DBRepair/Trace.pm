package Plugins::DBRepair::Trace;
use strict;
use warnings;
use JSON::XS;
use Time::HiRes qw(time);
use Scalar::Util qw(refaddr);
use File::Spec;
use File::Path qw(make_path);
use Carp qw(longmess);

my ($dir,$database,$role,$session,$counter,$installed,$loggingError);
my (@stack,%original,%wrappers,%callbacks);
our $MAX_BYTES=2*1024*1024;
our $MAX_FILES=24;
sub configure {
    ($dir,$database,$role)=@_;
    $session=$$.'-'.int(time()*1000000);$counter=0;
}
sub enabled {return $dir && -f File::Spec->catfile($dir,'trace.enabled') ? 1:0;}
sub active {scalar @stack}
sub current_ids {[map {$_->{operation_id}} @stack]}
sub logging_error {$loggingError||''}
sub emit {
    my ($event)=@_;
    local $@;
    eval {
        make_path($dir) unless -d $dir;
        my $path=File::Spec->catfile($dir,"trace-$session.jsonl");
        if (-f $path && -s $path > $MAX_BYTES) {
            unlink "$path.3" if -f "$path.3";
            for my $n (reverse 1..2) {rename "$path.$n","$path.".($n+1) if -f "$path.$n";}
            rename $path,"$path.1" or die $!;
        }
        open my $fh,'>>:raw',$path or die $!;
        print {$fh} encode_json({timestamp=>0+sprintf('%.6f',time()),pid=>$$,role=>$role,session=>$session,database_path=>$database,connection_id=>undef,connection_note=>'Verbindungskennung direkt an SQL-Ereignissen; kein zusaetzlicher DB-Zugriff fuer Root-Ereignisse.',%$event})."\n" or die $!;
        close $fh or die $!;
        # Each process writes a different file. Limit aggregate retained trace
        # files; protected reports embed their own immutable timeline snapshot.
        opendir my $dh,$dir or die $!;
        my @files=grep {/\Atrace-\d+-\d+\.jsonl(?:\.[123])?\z/} readdir $dh;closedir $dh;
        @files=sort { ((stat(File::Spec->catfile($dir,$b)))[9]||0) <=> ((stat(File::Spec->catfile($dir,$a)))[9]||0) } @files;
        if (@files>$MAX_FILES) {for my $file (@files[$MAX_FILES..$#files]) {next if $file eq "trace-$session.jsonl";unlink File::Spec->catfile($dir,$file);}}
        1;
    } or $loggingError="$@";
}
sub _invoke {
    my $meta=shift;my $cb=shift;
    return $cb->(@_) unless enabled() || @stack;
    my $want=wantarray;my (@out,$out,$error,$ok,$sqlcode,$sqlmessage);
    if ($meta->{connection_id}) {for my $ancestor (@stack) {$ancestor->{observed_connections}{$meta->{connection_id}}=1;}}
    my $parent=@stack?$stack[-1]{operation_id}:undef;
    my $span={%$meta,operation_id=>"$session-".(++$counter),parent_operation_id=>$parent,depth=>scalar @stack,caller_chain=>longmess('')};
    push @stack,$span;emit({%$span,event=>'begin'});
    {
        local $@;
        $ok=eval {if (!defined $want) {$cb->(@_);} elsif ($want) {@out=$cb->(@_);} else {$out=$cb->(@_);}1;};
        $error=$@;
        $sqlcode=$DBI::err;
        $sqlmessage=$DBI::errstr;
    }
    my $returnedError=$ok && $meta->{kind}=~/^sql_/ && $sqlcode;
    $error=$sqlmessage if $returnedError;
    if ($span->{observed_connections}) {
        my @connections=sort keys %{$span->{observed_connections}};
        $span->{connection_ids}=\@connections;
        $span->{connection_id}=$connections[0] if @connections==1;
        $span->{connection_note}='Aus tatsaechlich beobachteten SQL-Aufrufen dieser Operation abgeleitet.';
    }
    emit({%$span,event=>$ok&&!$returnedError?'end':'error',($ok&&!$returnedError?(): (error=>"$error",sqlite_code=>$sqlcode,raised_exception=>$ok?0:1,phase=>$meta->{phase}||$meta->{kind}))});
    pop @stack;
    die $error unless $ok;
    return $want ? @out : $out;
}
sub phase {
    my ($sql)=@_;$sql||='';
    return 'delete_track_assignments' if $sql =~ /\bDELETE\s+FROM\s+["`\[]?library_track\b/i;
    return 'fill_track_assignments' if $sql =~ /\b(?:INSERT|REPLACE)\b.*?\blibrary_track\b/is;
    return 'build_album_helpers' if $sql =~ /\b(?:DELETE|INSERT|REPLACE)\b.*?\blibrary_album\b/is;
    return 'build_artist_helpers' if $sql =~ /\b(?:DELETE|INSERT|REPLACE)\b.*?\blibrary_contributor\b/is;
    return 'build_genre_helpers' if $sql =~ /\b(?:DELETE|INSERT|REPLACE)\b.*?\blibrary_genre\b/is;
    return 'read_during_update' if $sql =~ /^\s*(?:SELECT|PRAGMA|WITH)\b/i;
    return 'other_sql';
}
sub hook {
    my ($name,$factory)=@_;no strict 'refs';no warnings 'redefine';
    return unless defined &{$name};
    my $old=\&{$name};my $new=$factory->($old);
    $original{$name}=$old;$wrappers{$name}=$new;*{$name}=$new;
}
sub wrap_callbacks {
    my ($args)=@_;return unless ref($args) eq 'HASH';
    for my $key (qw(scannerCB unregisterCB)) {
        my $cb=$args->{$key};next unless ref($cb) eq 'CODE';
        next if $callbacks{refaddr($cb)};
        my $id=$args->{id};
        my $wrapped=sub {return _invoke({kind=>$key,phase=>$key eq 'scannerCB'?'selection_callback':'unregister_callback',library_id=>$id},$cb,@_)};
        $callbacks{refaddr($wrapped)}={args=>$args,key=>$key,original=>$cb,wrapper=>$wrapped};
        $args->{$key}=$wrapped;
    }
}
sub install {
    return if $installed;
    require Slim::Music::VirtualLibraries;require DBI;
    for my $method (qw(registerLibrary unregisterLibrary rebuild)) {
        hook('Slim::Music::VirtualLibraries::'.$method,sub {my($old)=@_;return sub {
            if ($method eq 'registerLibrary') {local $@;eval {wrap_callbacks($_[1])};}
            my $id=ref($_[1]) eq 'HASH'?$_[1]{id}:$_[1];
            return _invoke({kind=>$method,library_id=>$id},$old,@_);
        }});
    }
    # Existing registrations retain their callbacks, wrapped rather than replaced.
    {local $@;eval {my $libs=Slim::Music::VirtualLibraries->getLibraries;wrap_callbacks($_) for values %$libs;};}
    for my $method (qw(do prepare prepare_cached selectall_arrayref selectrow_array selectcol_arrayref)) {
        hook('DBI::db::'.$method,sub {my($old)=@_;return sub {
            return $old->(@_) unless @stack;
            my $sql=$_[1]||'';my $p=phase($sql);
            return _invoke({kind=>'sql_'.$method,phase=>$p,library_id=>$stack[-1]{library_id},connection_id=>$$.':'.refaddr($_[0]),statement=>substr($sql,0,4000)},$old,@_);
        }});
    }
    hook('DBI::st::execute',sub {my($old)=@_;return sub {
        return $old->(@_) unless @stack;
        my $sql=$_[0]{Statement}||'';my $db=$_[0]{Database};
        my $bound=($sql=~/\blibrary_(?:track|album|contributor|genre)\b/i && defined($_[1]) && !ref($_[1]))?$_[1]:undef;
        return _invoke({kind=>'sql_execute',phase=>phase($sql),library_id=>$stack[-1]{library_id},first_bound_value=>$bound,connection_id=>$$.':'.refaddr($db),statement=>substr($sql,0,4000)},$old,@_);
    }});
    hook('Slim::Control::Request::notifyFromArray',sub {my($old)=@_;return sub {
        return $old->(@_) unless @stack && ref($_[1]) eq 'ARRAY' && ($_[1][0]||'') eq 'library';
        return _invoke({kind=>'notification',phase=>'change_notification',library_id=>$stack[-1]{library_id}},$old,@_);
    }});
    $installed=1;
    emit({event=>'instrumentation_start',kind=>'coverage',coverage=>'register/unregister/rebuild; existing and future scannerCB/unregisterCB; DBI SQL only inside observed operations; notification. Earlier startup events and reads outside observed operations are not covered.'}) if enabled();
}
sub uninstall {
    emit({event=>'instrumentation_end',kind=>'coverage'}) if $installed && enabled();
    no strict 'refs';no warnings 'redefine';
    for my $name (keys %original) {*{$name}=$original{$name} if defined(&{$name}) && refaddr(\&{$name})==refaddr($wrappers{$name});}
    for my $entry (values %callbacks) {my $now=$entry->{args}{$entry->{key}}; $entry->{args}{$entry->{key}}=$entry->{original} if ref($now) eq 'CODE' && refaddr($now)==refaddr($entry->{wrapper});}
    %original=();%wrappers=();%callbacks=();$installed=0;
}
sub timeline {
    my ($folder,$from,$to)=@_;my (@events,@sources);my $malformed=0;
    if (opendir(my $dh,$folder)) {
        my @files=sort grep {/\Atrace-\d+-\d+\.jsonl(?:\.[123])?\z/} readdir $dh;closedir $dh;
        for my $file (@files) {
            open my $fh,'<:raw',File::Spec->catfile($folder,$file) or next;push @sources,$file;
            while(my $line=<$fh>) {my $e=eval {decode_json($line)};if ($e) {push @events,$e;}else {$malformed++;}}
            close $fh;
        }
    }
    @events=sort {$a->{timestamp}<=>$b->{timestamp} || ($a->{operation_id}||'') cmp ($b->{operation_id}||'')} @events;
    my (%begins,%ends,@intervals,@incomplete,@nested,@overlaps,@reads);
    for my $e (@events) {
        next unless $e->{operation_id};
        $begins{$e->{operation_id}}=$e if $e->{event} eq 'begin';
        $ends{$e->{operation_id}}=$e if $e->{event} eq 'end'||$e->{event} eq 'error';
    }
    for my $id (keys %begins) {
        my $b=$begins{$id};my $end=$ends{$id};
        if ($end && !$b->{connection_id} && $end->{connection_ids}) {$b->{connection_id}=$end->{connection_id};$b->{connection_ids}=$end->{connection_ids};$b->{connection_note}=$end->{connection_note};}
        next if defined($from) && $end && $end->{timestamp}<$from;
        next if defined($to) && $b->{timestamp}>$to;
        push @incomplete,{operation_id=>$id,begin=>$b,reason=>'Ende fehlt: noch aktiv, Abbruch/Neustart oder Protokollrotation; nicht eindeutig zuordenbar.'} unless $end;
        if (($b->{phase}||'') eq 'read_during_update') {push @reads,{operation_id=>$id,parent_operation_id=>$b->{parent_operation_id},timestamp=>$b->{timestamp},pid=>$b->{pid}};}
        next unless $b->{kind} eq 'rebuild';
        my $item={%$b,end_timestamp=>$end?$end->{timestamp}:undef};push @intervals,$item;
        my $ancestor=$b->{parent_operation_id};
        while ($ancestor && $begins{$ancestor}) {if ($begins{$ancestor}{kind} eq 'rebuild') {push @nested,{outer=>$ancestor,inner=>$id};last;}$ancestor=$begins{$ancestor}{parent_operation_id};}
    }
    @intervals=sort {$a->{timestamp}<=>$b->{timestamp}} @intervals;
    for my $i (0..$#intervals) {for my $j ($i+1..$#intervals) {
        my($a,$b)=@intervals[$i,$j];next if $a->{pid}==$b->{pid};
        next unless defined $a->{end_timestamp} && defined $b->{end_timestamp};
        last if $b->{timestamp}>$a->{end_timestamp};
        push @overlaps,{first=>$a->{operation_id},second=>$b->{operation_id},classification=>'temporal_overlap_not_proven_sqlite_write_conflict'};
    }}
    my @selected=grep {(!defined($from)||$_->{timestamp}>=$from)&&(!defined($to)||$_->{timestamp}<=$to)} @events;
    my @orphanEnds=map {$ends{$_}} grep {!$begins{$_}} keys %ends;
    return {events=>\@selected,source_files=>\@sources,incomplete_operations=>\@incomplete,ends_without_begin=>\@orphanEnds,nested_rebuilds=>\@nested,cross_process_overlaps=>\@overlaps,instrumented_reads_during_update=>\@reads,rebuild_intervals=>\@intervals,related_operation_ids=>[sort map {$_->{operation_id}} @intervals],malformed_lines=>$malformed,attribution=>@incomplete||@orphanEnds?'ambiguous_incomplete_intervals':'observed_time_interval_only',warning=>'Zeitliche Ueberschneidung ist kein nachgewiesener SQLite-Schreibkonflikt. Protokollierung beginnt erst nach Instrumentierung, ist begrenzt und kann Luecken haben.'};
}
1;
