(function () {
    'use strict';
    var root = document.getElementById('dbrepair');
    if (!root || root.dataset.bound) return;
    root.dataset.bound = '1';
    function tr(de, en) { return root.dataset.language === 'de' ? de : en; }
    // Also reorder pages still served from LMS's compiled template cache.
    if (root.querySelector) {
        var restartButton = root.querySelector('button[data-action="restart"]');
        var heading = root.querySelector('h2');
        if (restartButton && heading) heading.insertAdjacentElement('afterend', restartButton.closest('section'));
    }
    var form = root.closest('form');
    var action = document.getElementById('dbrepair-action');
    var confirmation = document.getElementById('dbrepair-confirmation');
    var sending = false;
    var mode = document.getElementById('dbrepair-check-mode');
    var backupField = document.getElementById('dbrepair-compare-backup');
    if (mode && backupField) {
        mode.onchange = function () { backupField.hidden = mode.value !== 'compare'; };
        mode.onchange();
    }
    root.querySelectorAll('.dbrepair-copy').forEach(function (button) {
        button.onclick = function () {
            var report = button.closest('.dbrepair-report');
            var text = report.querySelector('.dbrepair-report-json').textContent;
            var status = report.querySelector('.dbrepair-copy-status');
            function fallback() {
                var field = document.createElement('textarea');
                field.value = text;
                field.setAttribute('aria-label', tr("Pruefprotokoll zum manuellen Kopieren","Report for manual copying"));
                report.appendChild(field); field.focus(); field.select();
                var copied = false;
                try { copied = document.execCommand('copy'); } catch (_) {}
                if (copied) { field.remove(); status.textContent = tr(" Protokoll kopiert."," Report copied."); }
                else { status.textContent = tr(" Bitte den markierten Text mit Strg+C kopieren."," Please copy the selected text using Ctrl+C."); }
            }
            if (window.isSecureContext && navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(function () { status.textContent = tr(" Protokoll kopiert."," Report copied."); }).catch(fallback);
            } else { fallback(); }
        };
    });
    function cleanURL() {
        var url = new URL(window.location.href);
        ['saveSettings', 'dbrepair_action', 'confirmation', 'backup_id'].forEach(function (key) { url.searchParams.delete(key); });
        return url.href;
    }
    document.getElementById('dbrepair-refresh').onclick = function () { window.location.replace(cleanURL()); };
    root.querySelectorAll('button[data-action]').forEach(function (button) {
        button.onclick = function () {
            if (sending || !form) return;
            var selected = button.dataset.action === 'diagnose' ? mode.value : button.dataset.action;
            if (selected === 'database_operation') selected = document.getElementById('dbrepair-operation').value;
            var messages = {
                backup: tr("Aktuelle Datenbank als neuen Sicherungsstand kopieren? LMS wird dafuer kurz gestoppt und danach mit derselben Datenbank gestartet. Wiedergabe und Oberflaeche werden unterbrochen; kein Neuaufbau wird angefordert.","Copy the current database into a new backup? LMS will briefly stop and then restart with the same database. Playback and the web interface will be interrupted; no rebuild will be requested."),
                trace_on: tr("Beobachtende Ablaufdiagnose einschalten? Sie erzeugt begrenzte Protokolldateien und zusaetzliche Diagnosearbeit.","Enable observational tracing? This creates bounded log files and adds diagnostic overhead."),
                trace_off: tr("Ablaufdiagnose ausschalten?","Disable tracing?"),
                trace_export: tr("Die vorhandenen Ablaufprotokolle zu einem Bericht zusammenfuehren?","Combine the existing trace logs into a report?"),
                protect: tr("Diesen Bericht einschliesslich gespeicherter Kontext- und Ablaufdaten dauerhaft vor automatischer Bereinigung schuetzen?","Permanently protect this report, including saved context and trace data, from automatic cleanup?"),
                quick_check: tr("Schnellpruefung der Datenbank starten? Es werden keine Daten repariert oder geloescht.","Start a quick database check? No data will be repaired or deleted."),
                integrity_check: tr("Vollstaendige Datenbankpruefung starten? Sie kann einige Minuten dauern und zusaetzliche Last erzeugen.","Start a full integrity check? This may take several minutes and increase load."),
                compare: tr("Aktuelle Datenbank und ausgewaehltes Backup vollstaendig pruefen und vergleichen? Beide Datenbanken bleiben unveraendert.","Fully check and compare the current database and selected backup? Both databases will remain unchanged."),
                restart: tr("LMS jetzt einmal neu starten? Die laufende Wiedergabe wird unterbrochen.","Restart LMS once now? Current playback will be interrupted."),
                reset: tr("Die aktive Musikdatenbank sichern, entfernen und vollstaendig neu einlesen? LMS und die Wiedergabe werden unterbrochen.","Back up and remove the active music database, then fully rescan it? LMS and playback will be interrupted.")
            };
            if (selected === 'compare' && !form.querySelector('[name="compare_backup_id"]').value) {
                window.alert(tr("Bitte zuerst eine Sicherung fuer den Vergleich auswaehlen.","Please select a backup for comparison first.")); return;
            }
            if (selected === 'delete') {
                var backup = form.querySelector('[name="backup_id"]').value;
                if (!backup) { window.alert(tr("Bitte zuerst eine Sicherung auswaehlen.","Please select a backup first.")); return; }
                messages.delete = tr("Sicherung ","Permanently delete backup ") + backup + tr(" endgueltig loeschen?","?");
            }
            if (!window.confirm(messages[selected])) return;
            sending = true;
            action.value = selected;
            confirmation.value = '1';
            if (selected === 'protect') document.getElementById('dbrepair-report-id').value = button.dataset.reportId;
            var save = document.createElement('input');
            save.type = 'hidden'; save.name = 'saveSettings'; save.value = '1';
            form.appendChild(save);
            form.method = 'post';
            root.querySelectorAll('button[data-action]').forEach(function (b) { b.disabled = true; });
            // Keep LMS's existing form action and CSRF fields.
            HTMLFormElement.prototype.submit.call(form);
        };
    });
    // Poll using GET only: refreshing a submitted POST must never replay an action.
    if (root.dataset.busy === '1') {
        var attempts = 0;
        function poll() {
            if (++attempts > 120) return;
            fetch(cleanURL(), {credentials: 'same-origin', cache: 'no-store'})
                .then(function (response) { if (!response.ok) throw new Error('offline'); return response.text(); })
                .then(function (html) {
                    var next = new DOMParser().parseFromString(html, 'text/html').getElementById('dbrepair');
                    if (next && next.dataset.busy === '0') { window.location.replace(cleanURL()); return; }
                    setTimeout(poll, 5000);
                }).catch(function () { setTimeout(poll, 5000); });
        }
        setTimeout(poll, 5000);
    }
}());
