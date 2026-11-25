package Plugins::DBRepair::Compare;
use strict;
use warnings;
use JSON::XS;
use Time::HiRes qw(time);
use Plugins::DBRepair::Check;
sub json { JSON::XS->new->canonical->encode($_[0]) }
sub capture {
    my ($dbh)=@_;
    my $schema=$dbh->selectall_arrayref("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE type IN ('table','index') ORDER BY type,name",{Slice=>{}});
    my %tables;
    for my $entry (@$schema) {
        if ($entry->{type} eq 'table') {
            $tables{$entry->{name}}=1;
            $entry->{columns}=$dbh->selectall_arrayref('PRAGMA table_info('.$dbh->quote_identifier($entry->{name}).')',{Slice=>{}});
        } else {
            $entry->{columns}=$dbh->selectall_arrayref('PRAGMA index_info('.$dbh->quote_identifier($entry->{name}).')',{Slice=>{}});
        }
    }
    my %counts;
    for my $table(qw(tracks albums library_track)) {
        $counts{$table}=$tables{$table} ? $dbh->selectrow_array('SELECT count(*) FROM '.$dbh->quote_identifier($table)) : undef;
    }
    my $rows=$dbh->selectall_arrayref('SELECT id,url FROM tracks',{Slice=>{}});
    my (%urls,%ids,%memberships);my $unmatched=0;
    for my $row (@$rows) {
        if (!defined($row->{url}) || $row->{url} eq '') {$unmatched++;next;}
        push @{$urls{$row->{url}}},$row->{id};$ids{$row->{id}}=$row->{url};
    }
    my $orphan=0;
    if ($tables{library_track}) {
        my $sth=$dbh->prepare('SELECT library,track FROM library_track');$sth->execute;
        while(my $row=$sth->fetchrow_arrayref) {
            if (!exists $ids{$row->[1]}) {$orphan++;next;}
            push @{$memberships{$ids{$row->[1]}}},defined($row->[0])?"$row->[0]":'<NULL>';
        }
    }
    return {schema=>$schema,counts=>\%counts,urls=>\%urls,memberships=>\%memberships,unmatchable_tracks=>$unmatched,orphan_memberships=>$orphan,membership_available=>$tables{library_track}?1:0};
}
sub run {
    my ($current,$backup,$label,$context)=@_;
    my $start=time();$context={%{$context||{}},deadline=>$start+600};
    my (@snapshots,@checks);
    for my $path ($current,$backup) {
        my $snapshot;
        push @checks,Plugins::DBRepair::Check::run($path,'integrity_check',$label,$context,sub {$snapshot=capture($_[0])});
        push @snapshots,$snapshot;
    }
    $checks[0]{database}{kind}='original';$checks[1]{database}{kind}='backup';
    my $result={schema_version=>3,mode=>'compare',check_id=>$context->{check_id},label=>$label,trigger=>'manual',started=>Plugins::DBRepair::Check::utc($start),finished=>Plugins::DBRepair::Check::utc(time()),seconds=>sprintf('%.2f',time()-$start),server_start=>$context,database=>$checks[0]{database},backup=>$checks[1]{database},command=>'PRAGMA integrity_check(2147483647) on both databases; read-only schema/count/URL/membership comparison',checks=>\@checks,state=>'error',output_complete=>0,messages=>[],notes=>['Zwei getrennte Lesetransaktionen: Live-Daten und Sicherung werden nacheinander gelesen.','Titelzuordnung per exakter URL; geaenderte Pfade erscheinen als entfernt/hinzugefuegt. Interne Titel-IDs werden nicht verglichen.','Bibliothekskennungen werden unveraendert verglichen; neu vergebene Kennungen beweisen keine inhaltliche Aenderung.']};
    if ((grep {!defined($_)} @snapshots) || (grep {$_->{state} eq 'error'} @checks)) {
        $result->{messages}=['Vergleich unvollstaendig: Mindestens eine Datenbank konnte nicht vollstaendig gelesen werden. Einzelpruefungen siehe JSON.'];return $result;
    }
    my ($a,$b)=@snapshots;
    $result->{counts}={current=>$a->{counts},backup=>$b->{counts}};
    $result->{schema}={current=>$a->{schema},backup=>$b->{schema},changed=>json($a->{schema}) ne json($b->{schema})?1:0};
    my %nowSchema=map {($_->{type}.':'.$_->{name})=>$_} @{$a->{schema}};
    my %oldSchema=map {($_->{type}.':'.$_->{name})=>$_} @{$b->{schema}};
    $result->{schema}{only_current}=[sort grep {!exists $oldSchema{$_}} keys %nowSchema];
    $result->{schema}{only_backup}=[sort grep {!exists $nowSchema{$_}} keys %oldSchema];
    $result->{schema}{changed_objects}=[sort grep {exists $oldSchema{$_} && json($nowSchema{$_}) ne json($oldSchema{$_})} keys %nowSchema];
    my (@added,@removed,@changed,@ambiguous);
    for my $url (sort keys %{$a->{urls}}) {push @added,$url unless exists $b->{urls}{$url};}
    for my $url (sort keys %{$b->{urls}}) {push @removed,$url unless exists $a->{urls}{$url};}
    for my $url (sort keys %{$a->{urls}}) {
        next unless exists $b->{urls}{$url};
        if (@{$a->{urls}{$url}}>1 || @{$b->{urls}{$url}}>1) {push @ambiguous,$url;next;}
        next unless $a->{membership_available} && $b->{membership_available};
        my @now=sort @{$a->{memberships}{$url}||[]};my @old=sort @{$b->{memberships}{$url}||[]};
        push @changed,{url=>$url,current=>\@now,backup=>\@old} if json(\@now) ne json(\@old);
    }
    $result->{differences}={added_urls=>\@added,removed_urls=>\@removed,changed_memberships=>\@changed,ambiguous_common_urls=>\@ambiguous,membership_comparison_available=>$a->{membership_available}&&$b->{membership_available}?1:0,unmatchable_tracks=>{current=>$a->{unmatchable_tracks},backup=>$b->{unmatchable_tracks}},orphan_memberships=>{current=>$a->{orphan_memberships},backup=>$b->{orphan_memberships}}};
    $result->{output_complete}=1;
    $result->{state}=(grep {$_->{state} ne 'ok'} @checks)?'findings':'ok';
    $result->{messages}=[sprintf('Vergleich abgeschlossen: %d hinzugefuegte URLs, %d entfernte URLs, %d geaenderte Bibliothekszuordnungen, %d mehrdeutige gemeinsame URLs.',scalar @added,scalar @removed,scalar @changed,scalar @ambiguous),$result->{schema}{changed}?'Datenbankschema unterscheidet sich.':'Datenbankschema stimmt ueberein.','OK beschreibt die Integritaet; Bestandsunterschiede sind nicht automatisch Datenbankfehler.'];
    return $result;
}
1;
