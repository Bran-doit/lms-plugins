const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const code=fs.readFileSync('Plugins/DBRepair/HTML/EN/plugins/DBRepair/settings/actions.js','utf8');
function setup(language,accept,selected='backup') {
 const buttons=['restart','reset','backup','delete','diagnose','trace_on','trace_off','trace_export','protect'].map(action=>({dataset:{action,reportId:'check-1-2.json'}}));
 const action={value:''},confirmation={value:''},refresh={},reportId={},mode={value:'compare'},backupField={};
 let submitted=0;const dialogs=[],alerts=[],fields=[];
 const form={appendChild:v=>fields.push(v),querySelector:()=>({value:'backup-id'})};
 const root={dataset:{language,busy:'0'},closest:()=>form,querySelectorAll:s=>s==='.dbrepair-copy'?[]:buttons};
 const document={getElementById:id=>({'dbrepair':root,'dbrepair-action':action,'dbrepair-confirmation':confirmation,'dbrepair-refresh':refresh,'dbrepair-report-id':reportId,'dbrepair-check-mode':mode,'dbrepair-compare-backup':backupField,'dbrepair-operation':{value:selected}}[id]),createElement:()=>({})};
 const window={confirm:s=>{dialogs.push(s);return accept;},alert:s=>alerts.push(s),location:{href:'http://localhost/',replace:()=>{}}};
 vm.runInNewContext(code,{document,window,URL,HTMLFormElement:{prototype:{submit(){submitted++;}}}});
 return {buttons,dialogs,action,confirmation,reportId,submitted:()=>submitted,root};
}
for(const lang of ['de','en','fr',undefined]) {
 for(let i=0;i<9;i++) {
  const ui=setup(lang,true);ui.buttons[i].onclick();ui.buttons[i].onclick();
  assert.equal(ui.submitted(),1);assert.equal(ui.dialogs.length,1);assert.ok(ui.dialogs[0]);assert.equal(ui.confirmation.value,'1');
  const cancelled=setup(lang,false);cancelled.buttons[i].onclick();assert.equal(cancelled.submitted(),0);
 }
 const ui=setup(lang,true);ui.buttons[0].onclick();assert.match(ui.dialogs[0],lang==='de'?/neu starten/:/Restart LMS/);
 const removal=setup(lang,true);removal.buttons[3].onclick();assert.match(removal.dialogs[0],/backup-id/);assert.match(removal.dialogs[0],lang==='de'?/loeschen/:/Permanently delete/);
 for(const op of ['backup','reset']){const x=setup(lang,true,op);x.buttons[0].dataset.action='database_operation';x.buttons[0].onclick();assert.equal(x.action.value,op);}
}
console.log('PASS: translated dialogs, English fallback, cancellation, one-time POST, IDs and database operation routing');
