package Plugins::DBRepair::Settings;
use strict;
use warnings;
use utf8;
use Plugins::DBRepair::I18N;
use Slim::Utils::Prefs;
use base qw(Slim::Web::Settings);
sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_DBREPAIR') }
sub page { Slim::Web::HTTP::CSRF->protectURI('plugins/DBRepair/settings/basic.html') }
sub handler {
    my ($class,$client,$params) = @_;
    my $language=Plugins::DBRepair::I18N::language(Slim::Utils::Prefs::preferences('server')->get('language'));
    $params->{dbrepair_language}=$language;
    $params->{dbrepair_t}=sub {Plugins::DBRepair::I18N::text($language,$_[0])};
    $params->{dbrepair_translate}=sub {Plugins::DBRepair::I18N::translate($language,$_[0])};
    if ($params->{saveSettings} && $params->{dbrepair_action}) {
        eval {
            if ($params->{dbrepair_action} =~ /\A(?:trace_on|trace_off|trace_export|protect)\z/) {
                die "Bitte Aktion bestaetigen" unless ($params->{confirmation}||'') eq '1';
                if ($params->{dbrepair_action} eq 'protect') {Plugins::DBRepair::Plugin::protectReport($params->{report_id},'manual');}
                elsif ($params->{dbrepair_action} eq 'trace_export') {Plugins::DBRepair::Plugin::exportTrace();}
                else {Plugins::DBRepair::Plugin::setTrace($params->{dbrepair_action} eq 'trace_on');}
                $params->{dbrepair_message}='Diagnoseeinstellung gespeichert.';
            } elsif ($params->{dbrepair_action} =~ /\A(?:quick_check|integrity_check|compare)\z/) {
                die "Bitte Prüfung bestätigen" unless ($params->{confirmation} || '') eq '1';
                Plugins::DBRepair::Plugin::startDiagnostic($params->{dbrepair_action},$params->{check_label} || 'manual',$params->{compare_backup_id});
                $params->{dbrepair_message} = 'Datenbankprüfung gestartet. Das Ergebnis erscheint nach Abschluss.';
            } else {
                Plugins::DBRepair::Plugin::submit($params->{dbrepair_action}, $params->{backup_id}, $params->{confirmation} || '');
                $params->{dbrepair_message} = 'Auftrag angenommen. Der Windows-Helfer startet innerhalb von etwa einer Minute.';
            }
            1;
        } or $params->{dbrepair_error} = "$@";
    }
    $params->{dbrepair} = Plugins::DBRepair::Plugin::state();
    return $class->SUPER::handler($client,$params);
}
1;
