use strict;
use warnings;
use utf8;
use Test::More;
use Template;
use JSON::XS;
use lib '.';
our $language;
BEGIN {
    $INC{'Slim/Web/Settings.pm'}=__FILE__;
    $INC{'Slim/Utils/Prefs.pm'}=__FILE__;
    package Slim::Web::Settings;sub handler {$_[2]}
    package Slim::Utils::Prefs;sub preferences {bless {},'LanguagePrefs'}
    package LanguagePrefs;sub get {$main::language}
    package Plugins::DBRepair::Plugin;
    sub startDiagnostic {1}
    sub state {{version=>'0.8.0',ready=>1,restartSupported=>1,backupSupported=>1,helperEvidenceSupported=>1,
        message=>'Datenbankkopie erstellt (test-id). LMS arbeitet mit der bisherigen Datenbank weiter; kein Neuaufbau angefordert.',
        checks=>[{mode=>'compare',label=>'manual',protection=>{reason=>'reference_healthy'},output_complete=>0,
        checks=>[{state=>'ok',database=>{kind=>'original',path=>'C:/Musik/Hörbücher/library.db'}},{state=>'error',database=>{kind=>'backup'},error=>{category=>'corruption',message=>'database disk image is malformed'}}],
        synchronous_warning=>'LMS synchronous=OFF: geringere Absicherung bei System- oder Stromausfall; kein Nachweis eines Plugin-Konflikts. Einstellung unveraendert.',
        details_json=>'ORIGINAL: Prüfung <unchanged>'}]}}
}
use Plugins::DBRepair::I18N;
use Plugins::DBRepair::Settings;
for my $case (['DE','de'],['de-DE','de'],['EN','en'],['FR','en'],['NL','en'],[undef,'en']) {
    is(Plugins::DBRepair::I18N::language($case->[0]),$case->[1],'Server language selects expected UI language');
}
my $tt=Template->new({INCLUDE_PATH=>'Plugins/DBRepair/HTML/EN',ENCODING=>'utf8',BLOCKS=>{'settings/header.html'=>'','settings/footer.html'=>''}});
for my $lang ('DE','EN','FR') {
    $language=$lang;
    my $params={saveSettings=>1,dbrepair_action=>'quick_check',confirmation=>1,language=>'DE'};
    Plugins::DBRepair::Settings->handler(undef,$params);
    my $out='';$tt->process('plugins/DBRepair/settings/basic.html',$params,\$out) or die $tt->error;
    if($lang eq 'DE') {
        like($out,qr/Server neu starten/,'German heading');
        like($out,qr/Datenbankprüfung gestartet/,'German action message');
        like($out,qr/Datenbankkopie erstellt \(test-id\)/,'German helper state');
        like($out,qr/Datenbankbeschädigung festgestellt/,'German backup finding');
    } else {
        like($out,qr/Restart server/,'English heading, also for unsupported language');
        like($out,qr/Database check started/,'English action message');
        like($out,qr/Database copy created \(test-id\)/,'Old helper message translated without helper update');
        like($out,qr/Database corruption detected/,'English backup finding');
        like($out,qr/reduced protection against system or power failure/,'English diagnostic warning');
        unlike($out,qr/Datenbankoperationen|Datenbankkopie erstellt|Prüfung fehlgeschlagen/,'No German presentation leaks');
    }
    like($out,qr/ORIGINAL: Prüfung &lt;unchanged&gt;/,'Original JSON content preserved and escaped');
    like($out,qr/C:\/Musik\/Hörbücher\/library.db/,'Database path not translated');
    unlike($out,qr/UI_\d+|MSG_\d+/,'No untranslated catalog keys');
}
is(Plugins::DBRepair::I18N::translate('en','Unbekannte Prüfung at Plugin.pm line 119.'),'Unknown check at Plugin.pm line 119.','Exception suffix preserved');
is(Plugins::DBRepair::I18N::translate('en','database disk image is malformed'),'database disk image is malformed','Native SQLite output unchanged');
is(Plugins::DBRepair::I18N::translate('en','Vergleich abgeschlossen: 1 hinzugefuegte URLs, 2 entfernte URLs, 3 geaenderte Bibliothekszuordnungen, 4 mehrdeutige gemeinsame URLs.'),'Comparison completed: 1 added URLs, 2 removed URLs, 3 changed library memberships, 4 ambiguous shared URLs.','Comparison counters preserved');
open my $fh,'<:raw','Plugins/DBRepair/i18n.json' or die $!;local $/;my $catalog=decode_json(<$fh>);close $fh;
ok(!grep({!length($_->{de}||'')||!length($_->{en}||'')} values %$catalog),'Every catalog entry has both languages');
done_testing();
