package Plugins::DBRepair::Evidence;
use strict;
use warnings;
use JSON::XS;
use File::Spec;
use Digest::SHA;
use Time::HiRes qw(time);

sub damage {
    my ($check)=@_;
    my (%groups,%indexes,%pages);
    for my $message (@{$check->{messages}||[]}) {
        for my $line (split /\n/,$message) {
            next if $line eq 'ok' || $line =~ /^\*\*\*/;
            my $group=$line =~ /freelist|free page|page.*(?:never used|multiple)|invalid page/i ? 'page_management'
                :$line =~ /index/i ? 'indexes' :$line =~ /tree|cell|rowid|overflow/i ? 'tree_structure' : 'other';
            push @{$groups{$group}},$line;
            $indexes{$1}=1 while $line =~ /\bindex\s+([\w.]+)/gi;
            $pages{$1}=1 while $line =~ /\bpage\s+(\d+)/gi;
        }
    }
    my @mapped;
    # Only map index names when an actual sqlite_master snapshot was captured.
    for my $entry (@{$check->{schema_objects}||[]}) {
        push @mapped,{index=>$entry->{name},table=>$entry->{tbl_name}} if $entry->{type} eq 'index' && $indexes{$entry->{name}};
    }
    return {groups=>\%groups,indexes=>[sort keys %indexes],pages=>[sort {$a<=>$b} keys %pages],verified_index_tables=>\@mapped,page_to_table_mapping=>'not_established',incomplete=>$check->{output_complete}?0:1,note=>$check->{output_complete}?'Kein Nachweis der Schadensursache.':'Weitere Schaeden moeglich; Ausgabe unvollstaendig.'};
}
sub backupEvidence {
    my ($database,$deadline)=@_;
    $deadline||=time()+30;
    my ($volume,$dir)=File::Spec->splitpath($database);
    my $folder=File::Spec->catpath($volume,$dir,'');
    my $path=File::Spec->catfile($folder,'manifest.json');
    my $result={consistency=>'unproven',message=>'Sicherungskonsistenz nicht belegt',historical_context=>undef,current_verification=>{}};
    return $result unless -f $path;
    eval {
        open my $fh,'<:raw',$path or die $!;local $/;my $manifest=decode_json(<$fh>);close $fh;
        $result->{manifest}=$manifest;
        $result->{historical_context}=$manifest->{creation_context};
        if ($manifest->{format_version} && $manifest->{format_version}>=2) {
            my @checks;
            for my $entry (@{$manifest->{file_evidence}||[]}) {
                my $name=$entry->{name};
                die 'Invalid manifest filename' unless defined($name) && $name =~ /\Alibrary\.db(?:-wal|-shm|-journal)?\z/;
                my $file=File::Spec->catfile($folder,$name);
                my $item={name=>$name,expected_sha256=>$entry->{sha256},expected_bytes=>$entry->{bytes}};
                if (-f $file) {
                    open my $in,'<:raw',$file or die $!;
                    my $sha=Digest::SHA->new(256);
                    while (1) {die 'Zeitlimit fuer Nachweispruefung erreicht' if time()>$deadline;my $n=read($in,my $buffer,1024*1024);die $! unless defined $n;last unless $n;$sha->add($buffer);}
                    $item->{actual_sha256}=$sha->hexdigest;close $in;
                    $item->{actual_bytes}=-s $file;
                    $item->{matches}=lc($item->{actual_sha256}) eq lc($entry->{sha256}||'') && $item->{actual_bytes}==$entry->{bytes} ? 1:0;
                } else {$item->{matches}=0;$item->{error}='File missing';}
                push @checks,$item;
            }
            $result->{current_verification}{files}=\@checks;
            my $e=$manifest->{creation_evidence}||{};
            my $hasDB=grep {$_->{name} eq 'library.db'} @checks;
            if ($hasDB && !(grep {!$_->{matches}} @checks) && ($e->{service_state}||'') eq 'Stopped' && $e->{scanner_absence_checked}) {
                $result->{consistency}='procedure_documented';
                $result->{message}='Sicherungsablauf dokumentiert und gespeicherte Pruefsummen stimmen. Kein Beweis fuer logische Fehlerfreiheit.';
            } elsif (grep {!$_->{matches}} @checks) {$result->{message}='Sicherungskonsistenz nicht belegt: Dateien fehlen oder weichen von gespeicherten Pruefsummen ab.';}
        }
        1;
    } or $result->{verification_error}="$@";
    return $result;
}
sub enrich {
    my ($report)=@_;
    my @checks=@{$report->{checks}||[$report]};
    for my $check (@checks) {
        $check->{damage_summary}=damage($check);
        $check->{context_scope}='today_check_not_backup_creation';
        my $connection=$check->{server_start}{connection}||{};
        if (defined($connection->{synchronous}) && "$connection->{synchronous}" =~ /^(?:0|OFF)$/i) {
            $check->{synchronous_warning}='LMS synchronous=OFF: geringere Absicherung bei System- oder Stromausfall; kein Nachweis eines Plugin-Konflikts. Einstellung unveraendert.';
        }
    }
    if ($report->{mode} eq 'compare') {
        my ($current,$backup)=@checks;
        my $state=sub {my($c)=@_;return 'intact' if $c->{state} eq 'ok';return 'damaged' if $c->{state} eq 'findings'||(($c->{error}||{})->{category}||'') eq 'corruption';return 'unknown';};
        $report->{outcomes}={current_integrity=>$state->($current),backup_integrity=>$state->($backup),content_comparison=>$report->{output_complete}?'complete':'not_possible'};
        $report->{backup_evidence}=backupEvidence($backup->{database}{path},($report->{server_start}{deadline}||time()+30));
        $report->{historical_context}=$report->{backup_evidence}{historical_context};
        $report->{historical_context_note}=$report->{historical_context}?'Kontext beim Erstellen der Sicherung, separat vom heutigen Pruefkontext.':'Historischer Plugin-/SQLite-Kontext nicht dokumentiert; heutige Werte beschreiben nicht den damaligen Zustand.';
    }
    return $report;
}
1;
