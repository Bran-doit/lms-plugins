package Plugins::DBRepair::Check;
use strict;
use warnings;
use DBI;
use Time::HiRes qw(time);
use Carp qw(longmess);
use Cwd qw(abs_path);
use POSIX qw(strftime);
sub utc { strftime('%Y-%m-%dT%H:%M:%SZ',gmtime($_[0])) }
sub run {
    my ($path,$mode,$label,$context,$collect)=@_;
    die "Invalid check" unless $mode eq 'quick_check' || $mode eq 'integrity_check';
    my $start=time();
    $context ||= {};
    my $command="PRAGMA $mode(2147483647)";
    my $result={schema_version=>2,check_id=>$context->{check_id} || join('-',int($start*1000000),$$),mode=>$mode,label=>$label||'',trigger=>'manual',started=>utc($start),started_epoch=>$start,state=>'error',messages=>[],command=>$command,output_complete=>0,database=>{path=>abs_path($path)||$path,kind=>'original',name=>'library.db'},process=>{diagnostic_pid=>$$},server_start=>$context,versions=>{perl=>"$^V",dbi=>$DBI::VERSION},connection=>{scope=>'diagnostic_connection',open_mode=>'SQLITE_OPEN_READONLY',snapshot=>'read_transaction'}};
    my $dbh;
    my $trace;
    local $SIG{__DIE__}=sub {$trace=longmess($_[0])};
    eval {
        die "Database missing or empty\n" unless -f $path && -s $path;
        $dbh=DBI->connect("dbi:SQLite:dbname=$path",'','',{RaiseError=>1,PrintError=>0,AutoCommit=>1,sqlite_open_flags=>1});
        $dbh->sqlite_busy_timeout(3000);
        $dbh->do('PRAGMA query_only=ON');
        $dbh->sqlite_progress_handler(10000,sub {time()>($context->{deadline}||$start+600) ? 1 : 0});
        $dbh->do('BEGIN');
        $result->{versions}{sqlite}=$dbh->selectrow_array('SELECT sqlite_version()');
        $result->{versions}{dbd_sqlite}=$DBD::SQLite::VERSION;
        for my $pragma (qw(journal_mode synchronous locking_mode busy_timeout query_only)) {
            $result->{connection}{$pragma}=$dbh->selectrow_array("PRAGMA $pragma");
        }
        my ($tracks)=$dbh->selectrow_array("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='tracks'");
        die "Not an LMS library: tracks table missing\n" unless $tracks;
        # An actual schema query is the only basis for assigning index names to tables.
        $result->{schema_objects}=$dbh->selectall_arrayref("SELECT type,name,tbl_name FROM sqlite_master WHERE type IN ('table','index')",{Slice=>{}});
        my $sth=$dbh->prepare($command);$sth->execute;
        while (my $row=$sth->fetchrow_arrayref) {push @{$result->{messages}},$row->[0];}
        my $rows=$result->{messages};
        $result->{output_complete}=1;
        $result->{state}=(@$rows==1 && $rows->[0] eq 'ok') ? 'ok' : 'findings';
        $collect->($dbh,$result) if $collect;
        $dbh->do('ROLLBACK');
        1;
    } or do {
        my $message="$@";
        my $code=$dbh ? $dbh->err : $DBI::err;
        my $primary=defined($code) && $code =~ /^\d+$/ ? ($code & 255) : undef;
        $result->{state}='error';
        $result->{output_complete}=0;
        $result->{error}={message=>$message,stack=>$trace||longmess($message),code=>$code,primary_code=>$primary,sqlstate=>$dbh?$dbh->state:$DBI::state,category=>defined($primary)&&($primary==11||$primary==26)?'corruption':defined($primary)&&($primary==5||$primary==6)?'locked':defined($primary)&&$primary==9?'interrupted':'execution_error'};
        push @{$result->{messages}},$message;
    };
    eval {$dbh->disconnect if $dbh};
    $result->{seconds}=sprintf('%.2f',time()-$start);
    $result->{finished}=utc(time());
    $result->{finished_epoch}=time();
    return $result;
}
1;
