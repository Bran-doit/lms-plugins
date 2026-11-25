use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use JSON::XS;
use DBI;
use lib '.';
use Plugins::DBRepair::Trace;
our ($dbh,%libs,@notifications,$inside);
BEGIN {
    $INC{'Slim/Music/VirtualLibraries.pm'}=__FILE__;
    package Slim::Music::VirtualLibraries;
    sub getLibraries {\%main::libs}
    sub registerLibrary {my($class,$args)=@_;$main::libs{$args->{id}}=$args;$class->rebuild($args->{id});return $args->{id};}
    sub unregisterLibrary {my($class,$id)=@_;$main::dbh->do('DELETE FROM library_track');delete $main::libs{$id};return 9;}
    sub rebuild {
        my($class,$id)=@_;$main::dbh->do('DELETE FROM library_track');
        $main::libs{$id}{scannerCB}->($id) if $main::libs{$id}{scannerCB};
        for my $table(qw(library_album library_contributor library_genre)) {
            my $sth=$main::dbh->prepare_cached("DELETE FROM $table");$sth->execute;
            $main::dbh->do("INSERT INTO $table VALUES(1)");
        }
        Slim::Control::Request::notifyFromArray(undef,['library','changed',1]);return 7;
    }
    package Slim::Control::Request;
    sub notifyFromArray {push @main::notifications,$_[1];return 1;}
}
my $dir=tempdir(CLEANUP=>1);
$dbh=DBI->connect("dbi:SQLite:dbname=$dir/db.sqlite",'','',{RaiseError=>1,PrintError=>0,AutoCommit=>1});
$dbh->do('CREATE TABLE library_track(track)');
$dbh->do("CREATE TABLE $_(id)") for qw(library_album library_contributor library_genre);
Plugins::DBRepair::Trace::configure($dir,"$dir/db.sqlite",'server');
Plugins::DBRepair::Trace::install();
open my $enabled,'>',"$dir/trace.enabled" or die $!;close $enabled;
my $callback=sub {
    $dbh->do('INSERT INTO library_track VALUES(1)');
    $dbh->selectrow_array('SELECT count(*) FROM library_track');
    $inside=Plugins::DBRepair::Trace::active();
    return wantarray?(2,3):5;
};
is(Slim::Music::VirtualLibraries->registerLibrary({id=>'test',scannerCB=>$callback}),'test','Registration return preserved');
ok($inside,'Callback is marked active');
is($dbh->selectrow_array('SELECT count(*) FROM library_track'),1,'Original callback performs its work');
is(scalar @notifications,1,'Original notification preserved');
is($libs{test}{scannerCB}->('test'),5,'Scalar callback return preserved');
my @list=$libs{test}{scannerCB}->('test');is_deeply(\@list,[2,3],'List callback return preserved');
is(Slim::Music::VirtualLibraries->rebuild('test'),7,'Rebuild return preserved');
my $timeline=Plugins::DBRepair::Trace::timeline($dir,undef,undef);
my %phases=map {($_->{phase}||'')=>1} @{$timeline->{events}};
ok($phases{$_},"Phase $_ captured") for qw(delete_track_assignments fill_track_assignments build_album_helpers build_artist_helpers build_genre_helpers change_notification read_during_update selection_callback);
my @rebuild=grep {$_->{kind} eq 'rebuild' && $_->{event} eq 'begin'} @{$timeline->{events}};
ok($rebuild[0]{parent_operation_id},'Registration-triggered rebuild has parent operation');
ok(@{$rebuild[0]{connection_ids}||[]},'Connection identities derived from actual child SQL');
my $bad=sub {die "original failure\n"};
eval {Slim::Music::VirtualLibraries->registerLibrary({id=>'bad',scannerCB=>$bad})};
is($@,"original failure\n",'Original exception preserved exactly');
ok(!Plugins::DBRepair::Trace::active(),'Stack unwound after error');
$timeline=Plugins::DBRepair::Trace::timeline($dir,undef,undef);
ok(grep($_->{event} eq 'error',@{$timeline->{events}}),'Errors recorded');
$libs{nested}={id=>'nested',scannerCB=>sub {}};
Slim::Music::VirtualLibraries->registerLibrary({id=>'outer',scannerCB=>sub {Slim::Music::VirtualLibraries->rebuild('nested')}});
$timeline=Plugins::DBRepair::Trace::timeline($dir,undef,undef);
ok(@{$timeline->{nested_rebuilds}},'Nested rebuild explicitly detected');
# Observation must not commit the caller's transaction.
$dbh->{AutoCommit}=0;
Slim::Music::VirtualLibraries->rebuild('test');
ok(!$dbh->{AutoCommit},'Autocommit not changed');$dbh->rollback;$dbh->{AutoCommit}=1;
my $before=scalar @{$timeline->{events}};
unlink "$dir/trace.enabled";
Slim::Music::VirtualLibraries->rebuild('test');
my $disabled=Plugins::DBRepair::Trace::timeline($dir,undef,undef);
my $count=scalar @{$disabled->{events}};
Slim::Music::VirtualLibraries->rebuild('test');
is(scalar @{Plugins::DBRepair::Trace::timeline($dir,undef,undef)->{events}},$count,'Disabled observer emits no events');
Plugins::DBRepair::Trace::uninstall();
is($libs{test}{scannerCB},$callback,'Original callback restored');
# Merge synthetic per-process logs and preserve incomplete intervals.
open my $file,'>:raw',"$dir/trace-1-1.jsonl" or die $!;
for my $event (
 {timestamp=>1,pid=>1,operation_id=>'a',kind=>'rebuild',event=>'begin'},
 {timestamp=>2,pid=>2,operation_id=>'b',kind=>'rebuild',event=>'begin'},
 {timestamp=>3,pid=>1,operation_id=>'a',kind=>'rebuild',event=>'end'},
 {timestamp=>4,pid=>2,operation_id=>'b',kind=>'rebuild',event=>'end'},
 {timestamp=>5,pid=>3,operation_id=>'crash',kind=>'rebuild',event=>'begin'}) {print {$file} encode_json($event)."\n";}
close $file;
$timeline=Plugins::DBRepair::Trace::timeline($dir,0,10);
is(scalar @{$timeline->{cross_process_overlaps}},1,'Cross-process temporal overlap detected');
is($timeline->{cross_process_overlaps}[0]{classification},'temporal_overlap_not_proven_sqlite_write_conflict','Overlap not mislabeled as conflict');
ok(@{$timeline->{incomplete_operations}},'Missing end is incomplete');
is($timeline->{attribution},'ambiguous_incomplete_intervals','Incomplete interval attributed cautiously');
open my $flag,'>',"$dir/trace.enabled" or die $!;close $flag;
Plugins::DBRepair::Trace::install();
{
    no warnings 'redefine';
    local *Plugins::DBRepair::Trace::emit=sub { };
    is(Plugins::DBRepair::Trace::_invoke({kind=>'test'},sub {42}),42,'Observer preserves return value without logging');
}
Plugins::DBRepair::Trace::configure("$dir/trace.enabled",'library.db','scanner');
Plugins::DBRepair::Trace::emit({event=>'test'});
ok(Plugins::DBRepair::Trace::logging_error(),'Logging failure isolated and exposed');
Plugins::DBRepair::Trace::configure($dir,'library.db','scanner');
Plugins::DBRepair::Trace::emit({event=>'role_test'});
my @scanner=grep {$_->{event} eq 'role_test'} @{Plugins::DBRepair::Trace::timeline($dir,undef,undef)->{events}};
is($scanner[0]{role},'scanner','Scanner role retained in merged timeline');
Plugins::DBRepair::Trace::uninstall();
$dbh->disconnect;
done_testing;
