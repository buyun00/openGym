import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {stampPut} from '../../api/sync-stamps.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {once} from 'node:events';
import {boundPort} from '../../api/test/helpers.mjs';

const bridge = new Function(readFileSync(new URL('../../frontend/ios/App/App/Native/GymSyncBridge.js', import.meta.url),'utf8')+'; return GymSyncBridge;')();
const copy = x => JSON.parse(JSON.stringify(x));
const catalogue = {'0585':{name:'坐姿腿屈伸',mode:'reps'}, '2259':{name:'跑步机',mode:'cardio'}};
function fixture() {
  return {unit:'kg',restSec:90,targetW:70,week:{0:['short-plan'],3:['short-plan']},dayPlan:{'2026-10-23':'short-plan'},
    routines:[{id:'short-plan',name:'全身力量',emoji:'💪',ex:[{id:'2259',sets:1,min:5,speed:4.5,note:'热身'},
      {id:'0585',sets:3,reps:10,weight:15,progression:{type:'double',step:2.5}}, {id:'2259',sets:1,min:3,speed:4.5,note:'放松'}]}],
    workouts:[{id:'workout-short',d:'2026-10-14',start:1791989400000,end:1791991200000,routineId:'short-plan',vol:150,
      entries:[{id:'0585',rid:'short-plan',target:{mode:'reps'},sets:[{w:15,r:10,done:true,rir:3,drops:[{w:10,r:3}],sides:{L:{w:15,r:10},R:{w:15,r:10}}}],muscleSnapshot:{quads:1}}]}],
    bodyweight:[{d:'2026-10-20',w:80,t:123}],measurements:[{d:'2026-10-20',chest:100,upperArmLeft:30,upperArmRight:31,bodyFat:20,other:{custom:9}}],
    customMeasurements:[{id:'custom',name:'自定义围度'}],gymEquipment:[{id:'eq1',name:'器械',photo:'sha256:123',exNames:['深蹲'],note:'座位3'}],
    exWeights:{'0585':15},edited:{theme:99},deleted:{bodyweight:{'2026-01-01':123}},_rev:9,_wid:'revision-nine',
    unknownFuture:{keep:['all','fields']}};
}
const project = s => bridge.projection(s,catalogue);
const prepare = (b,l,r) => bridge.prepare(b,l,r,catalogue);

test('HealthKit results survive upload, readback and unrelated web edits',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);
  const health={source:'apple_health',status:'available',window_start:raw.workouts[0].start,
    window_end:raw.workouts[0].end,queried_at:raw.workouts[0].end+1000,
    heart_rate_avg_bpm:125.2,heart_rate_max_bpm:160,active_energy_kcal:230};
  local.workouts[0].health=health;
  const remote=copy(raw); remote.workouts[0].note='web edit';
  const out=prepare(base,local,remote);
  assert.deepEqual(out.state.workouts[0].health,health);
  assert.equal(out.state.workouts[0].note,'web edit');
  assert.deepEqual(project(out.state).workouts[0].health,health);
  assert.equal(prepare(project(out.state),project(out.state),out.state).changed,false);
});

test('an unchanged native projection preserves the complete server document exactly',()=>{
  const raw=fixture(), view=project(raw), out=prepare(view,view,raw);
  assert.equal(out.changed,false); assert.deepEqual(out.state,raw);
});

test('manual health replacement is exact and explicit skip removes the previous record',()=>{
  const raw=fixture();
  raw.workouts[0].health={source:'apple_health',status:'available',workout_id:'old',heart_rate_avg_bpm:180};
  const base=project(raw),local=copy(base);
  const selected={source:'apple_health',status:'no_data',workout_id:'manual-choice',window_start:123,window_end:456,queried_at:789};
  local.workouts[0].health=selected;
  const uploaded=prepare(base,local,raw).state;
  assert.deepEqual(uploaded.workouts[0].health,selected); // No stale heart rate leaks into replacement.
  const selectedBase=project(uploaded),skipped=copy(selectedBase);
  skipped.workouts[0].health=null;
  const cleared=prepare(selectedBase,skipped,uploaded).state;
  assert.equal('health' in cleared.workouts[0],false);
  assert.equal(project(cleared).workouts[0].health,null);
});
test('Swift omits optional nil fields and JSON key order without causing writes',()=>{
  const raw=fixture(),base=project(raw);
  const compact=x=>Array.isArray(x)?x.map(compact):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).reverse().filter(k=>x[k]!=null).map(k=>[k,compact(x[k])])):x;
  assert.equal(prepare(base,compact(base),raw).changed,false);
});
test('web IDs remain stable and distinct for duplicate exercise slots',()=>{
  const view=project(fixture());
  assert.match(view.routines[0].id,/^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$/);
  assert.equal(view.routines[0].id,view.workouts[0].exercises[0].routineId);
  assert.notEqual(view.routines[0].exercises[0].id,view.routines[0].exercises[2].id);
  assert.equal(view.routines[0].exercises[1].weight,15);
  assert.equal(view.routines[0].exercises[0].mode,'cardio');
});
test('Sunday and date-specific plans project to native IDs',()=>{
  const raw=fixture(), view=project(raw);
  assert.deepEqual(view.week[6].routineIds,[view.routines[0].id]);
  assert.deepEqual(view.dayPlan['2026-10-23'],[view.routines[0].id]);
  const local=copy(view); local.week[6].routineIds=[];local.week[0].routineIds=[view.routines[0].id];
  const out=prepare(view,local,raw).state;
  assert.deepEqual(out.week['0'],[]);assert.deepEqual(out.week['1'],['short-plan']);
});
test('renaming a routine preserves IDs, progression, duplicate slots and web-only fields',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);local.routines[0].name='新计划';
  const out=prepare(base,local,raw).state;
  assert.equal(out.routines[0].id,'short-plan');assert.deepEqual(out.routines[0].ex,raw.routines[0].ex);
  assert.deepEqual(out.unknownFuture,raw.unknownFuture);assert.deepEqual(out.gymEquipment,raw.gymEquipment);
});
test('editing a single set preserves drop sets, sides, targets and muscle snapshots',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);local.workouts[0].exercises[0].sets[0].rir=2;
  const out=prepare(base,local,raw).state;
  const expected=copy(raw);expected.workouts[0].entries[0].sets[0].rir=2;
  assert.deepEqual(out,expected);
});
test('independent concurrent record edits merge without dropping server additions',()=>{
  const raw=fixture(),base=project(raw),local=copy(base),remote=copy(raw);
  local.routines[0].name='手机修改';remote.bodyweight.push({d:'2026-10-21',w:79});
  remote.gymEquipment.push({id:'eq2',name:'新增器械'});
  const out=prepare(base,local,remote).state;
  assert.equal(out.routines[0].name,'手机修改');assert.equal(out.bodyweight.length,2);assert.equal(out.gymEquipment.length,2);
});
test('same-field concurrent edit reports conflict and leaves inputs untouched',()=>{
  const raw=fixture(),base=project(raw),local=copy(base),remote=copy(raw);
  local.routines[0].name='手机';remote.routines[0].name='网页';const saved=copy(remote);
  assert.throws(()=>prepare(base,local,remote),/两端同时修改/);assert.deepEqual(remote,saved);
});
test('delete-versus-edit conflict is not silently overwritten',()=>{
  const raw=fixture(),base=project(raw),local=copy(base),remote=copy(raw);
  local.routines=[];remote.routines[0].name='网页';assert.throws(()=>prepare(base,local,remote),/两端同时修改/);
});
test('server deletion is retained when native did not edit that record',()=>{
  const raw=fixture(),base=project(raw),local=copy(base),remote=copy(raw);
  local.restSeconds=120;remote.workouts=[];
  const out=prepare(base,local,remote).state;assert.deepEqual(out.workouts,[]);assert.equal(out.restSec,120);
});
test('native deletes receive server tombstones so the web cannot resurrect them',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);local.workouts=[];
  const out=prepare(base,local,raw).state;
  stampPut(raw,out,{overRead:true,stamped:false,report:{}});
  assert.equal(out.workouts.length,0);assert.ok(out.deleted.workouts['workout-short']>0);
});
test('daily weights and asymmetric/custom measurements survive without reducing fields',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);
  assert.equal(base.weighIns[0].bodyFatPercent,20);
  assert.equal(base.bodyMeasurements[0].bodyFatPercent,20);
  assert.equal(base.bodyMeasurements[0].centimeters['左上臂围'],30);
  assert.equal(base.bodyMeasurements[0].centimeters['右上臂围'],31);
  local.bodyMeasurements[0].centimeters['胸围']=101;
  const out=prepare(base,local,raw).state;
  assert.equal(out.measurements[0].chest,101);assert.equal(out.measurements[0].other.custom,9);assert.equal(out.measurements[0].upperArmRight,31);
});
test('weight body-fat edits write to the shared measurement for that day',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);local.weighIns[0].bodyFatPercent=19;
  const out=prepare(base,local,raw).state;assert.equal(out.measurements[0].bodyFat,19);assert.equal(out.measurements[0].chest,100);
});
test('kg/lb and km/h/mph conversions preserve server units and untouched values',()=>{
  const raw=fixture();raw.unit='lb';raw.speedUnit='mph';
  const base=project(raw);assert.equal(base.weighIns[0].kilograms,80*0.45359237);
  assert.equal(prepare(base,base,raw).changed,false);
  const local=copy(base);local.weighIns[0].kilograms=70;
  const out=prepare(base,local,raw).state;assert.equal(out.unit,'lb');assert.equal(out.bodyweight[0].w,70/0.45359237);
});
test('new native workout uses the web history schema and original routine ID',()=>{
  const raw=fixture(),base=project(raw),local=copy(base),w=copy(base.workouts[0]);
  w.id='AAAAAAAA-BBBB-4CCC-ADDD-EEEEEEEEEEEE';w.exercises[0].id='BBBBBBBB-BBBB-4CCC-ADDD-EEEEEEEEEEEE';local.workouts.push(w);
  const out=prepare(base,local,raw).state.workouts[1];
  assert.equal(out.routineId,'short-plan');assert.equal(out.entries[0].id,'0585');assert.equal(out.entries[0].sets[0].w,15);
  assert.equal(out.entries[0].target.mode,'reps');assert.ok(out.end>out.start);
  assert.equal(project({...raw,workouts:[out]}).workouts[0].id,w.id);
});
test('local active workout is never included in a cloud write',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);local.active={private:true};local.restSeconds=100;
  assert.equal(prepare(base,local,raw).state.active,undefined);
});

test('standalone HealthKit import syncs as completed history without a plan or active session',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);
  const health={source:'apple_health',status:'available',workout_id:'B7F450E5-7462-451D-BF86-4BA5F8E7B223',
    window_start:1700000000000,window_end:1700003600000,queried_at:1700003601000,heart_rate_avg_bpm:130,active_energy_kcal:320};
  local.active={id:'unrelated-active-session'};
  local.workouts.push({id:health.workout_id,name:'骑行 · 健康导入',startedAt:1700000000,finishedAt:1700003600,
    exercises:[],note:'从 Apple 健康手动导入',health});
  const uploaded=prepare(base,local,raw).state;
  const imported=uploaded.workouts.find(w=>w.id===health.workout_id);
  assert.deepEqual(imported.entries,[]);
  assert.deepEqual(imported.routineIds,[]);
  assert.equal(imported.start,health.window_start);
  assert.equal(imported.end,health.window_end);
  assert.deepEqual(imported.health,health);
  assert.equal(uploaded.active,undefined);
  assert.deepEqual(local.active,{id:'unrelated-active-session'});
  assert.equal(prepare(project(uploaded),project(uploaded),uploaded).changed,false);
});
test('new local modifications during an upload can be rebased over the readback',()=>{
  const raw=fixture(),base=project(raw),sent=copy(base);sent.restSeconds=100;
  const readback=prepare(base,sent,raw).state;readback.bodyweight.push({d:'2026-10-21',w:79});
  const current=copy(sent);current.routines[0].name='上传期间的新编辑';
  const pending=prepare(sent,current,readback);assert.equal(pending.changed,true);
  assert.equal(pending.snapshot.weighIns.length,2);assert.equal(pending.snapshot.routines[0].name,'上传期间的新编辑');
});
test('new native routine and its weekly assignment refer to the same web ID',()=>{
  const raw=fixture(),base=project(raw),local=copy(base),r=copy(base.routines[0]);
  r.id='AAAAAAAA-BBBB-4CCC-ADDD-EEEEEEEEEEEE';local.routines.push(r);local.week[0].routineIds=[r.id];
  const out=prepare(base,local,raw).state;assert.equal(out.week['1'][0],out.routines[1].id);
});
test('adding equipment filters preserves actual gym inventory',()=>{
  const raw=fixture(),base=project(raw),local=copy(base);local.ownedEquipment=['dumbbell'];
  const out=prepare(base,local,raw).state;assert.deepEqual(out.gymEquipment,raw.gymEquipment);
  assert.deepEqual(out.equipProfiles[0].equipment,['dumbbell']);
});

test('real local API: browser pairing, first download, conditional write, readback and conflict retry',async t=>{
  // Isolated synthetic account. No production endpoint, credential or user data is used here.
  const tempRoot=fs.realpathSync(os.tmpdir());
  const dataDir=fs.mkdtempSync(path.join(tempRoot,'opengym-native-sync-'));
  assert.equal(path.dirname(fs.realpathSync(dataDir)),tempRoot);
  const secret=crypto.randomBytes(32).toString('hex'),uid='native-sync-fixture';
  fs.writeFileSync(path.join(dataDir,'secret'),secret);
  fs.writeFileSync(path.join(dataDir,'db.json'),JSON.stringify({users:[{id:uid,name:'Test',created:new Date().toISOString()}],creds:[],subs:[],invites:[]}));
  fs.writeFileSync(path.join(dataDir,`state-${uid}.json`),JSON.stringify(fixture()));
  const child=spawn(process.execPath,['server.js'],{cwd:fileURLToPath(new URL('../../api',import.meta.url)),stdio:['ignore','pipe','pipe'],
    env:{...process.env,PORT:'0',DATA_DIR:dataDir,ORIGIN:'http://localhost:8080',RP_ID:'localhost',COACH_DISABLED:'1',MEDIA_UPLOADS:'0'}});
  t.after(async()=>{
    if(child.exitCode===null){const stopped=once(child,'exit');child.kill();await stopped;}
    assert.equal(path.dirname(fs.realpathSync(dataDir)),tempRoot);
    fs.rmSync(dataDir,{recursive:true,force:true});
  });
  let log='';child.stdout.on('data',d=>log+=d);child.stderr.on('data',d=>log+=d);
  const port=await boundPort(child,()=>log),url=`http://127.0.0.1:${port}`;
  const payload=`${uid}:${Date.now()+86400000}:0`;
  const cookie=payload+'.'+crypto.createHmac('sha256',secret).update(payload).digest('base64url');
  const pair=await fetch(url+'/api/pair/create',{method:'POST',headers:{Cookie:'gymsid='+cookie,'Content-Type':'application/json'},body:'{}'});
  assert.equal(pair.status,200);const {code}=await pair.json();
  const redemption=await fetch(url+'/api/pair/redeem',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code})});
  assert.equal(redemption.status,200);const {token,user}=await redemption.json();assert.equal(user.id,uid);
  const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
  const get=()=>fetch(url+'/api/data',{headers}).then(r=>r.json());
  const put=body=>fetch(url+'/api/data',{method:'PUT',headers,body:JSON.stringify(body)});
  const first=await get(),base=project(first.state),local=copy(base);local.restSeconds=120;
  assert.deepEqual(first.state.routines,fixture().routines);
  const modified=prepare(base,local,first.state).state;
  assert.equal((await put({state:modified,baseRev:first.rev,baseWid:first.state._wid})).status,200);
  const synced=await get();assert.equal(synced.state.restSec,120);assert.equal(synced.state.bodyweight.length,1);
  assert.deepEqual(synced.state.gymEquipment,fixture().gymEquipment);
  assert.equal(prepare(project(synced.state),project(synced.state),synced.state).changed,false);
  const native=project(synced.state),edited=copy(native);edited.routines[0].name='手机计划';
  const web=copy(synced.state);web.bodyweight.push({d:'2026-10-22',w:78});
  assert.equal((await put({state:web,baseRev:synced.rev,baseWid:synced.state._wid})).status,200);
  const stale=await put({state:prepare(native,edited,synced.state).state,baseRev:synced.rev,baseWid:synced.state._wid});
  assert.equal(stale.status,409);
  const fresh=await get(),merged=prepare(native,edited,fresh.state).state;
  assert.equal((await put({state:merged,baseRev:fresh.rev,baseWid:fresh.state._wid})).status,200);
  const final=await get();assert.equal(final.state.bodyweight.length,2);assert.equal(final.state.routines[0].name,'手机计划');
  const me=await fetch(url+'/api/me',{headers}).then(r=>r.json());assert.equal(me.user.id,uid);
  const replay=await fetch(url+'/api/pair/redeem',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code})});
  assert.equal(replay.status,400);
});

test('native live events: start, all-sets completion, finish health, discard and history isolation', () => {
  const raw = fixture(), initial = project(raw);
  const w = {id:'B772D421-E418-4A34-A729-885000000001',name:'训练',startedAt:1793000000,
    exercises:[{id:'entry-1',exerciseId:'0585',name:'腿屈伸',routineId:bridge.uuid('short-plan'),
      sets:[{id:'set-1',weight:15,reps:10,done:false},{id:'set-2',weight:15,reps:8,done:false}]}]};
  const active = {...copy(initial),active:w};
  const events = (a,b) => bridge.workoutEvents(a,b,raw).events;
  const start = events(initial,active);
  assert.equal(start.length,1); assert.equal(start[0].type,'workout.started');
  assert.equal(start[0].data.started_at,1793000000000);
  assert.deepEqual(start[0].data.routine_ids,['short-plan']);
  assert.equal(start[0].data.exercises[0].planned_sets,2);
  const partial=copy(active); partial.active.exercises[0].sets[0].done=true;
  assert.equal(events(active,partial).length,0);
  const done=copy(partial); done.active.exercises[0].sets[1].done=true;
  done.active.exercises[0].sets[1].completedAt=1793000100;
  const exercise=events(partial,done)[0];
  assert.equal(exercise.type,'exercise.completed');
  assert.equal(exercise.data.exercise.sets[1].weight_kg,15);
  assert.equal(exercise.data.completed_at,1793000100000);
  assert.equal(events(done,copy(done)).length,0);
  const health={source:'apple_health',status:'available',heart_rate_avg_bpm:125,active_energy_kcal:210};
  const finished={...copy(done.active),finishedAt:1793000600,health};
  const saved={...copy(done),active:null,workouts:[...done.workouts,finished]};
  const completion=events(done,saved)[0];
  assert.equal(completion.type,'workout.completed'); assert.equal(completion.data.workout_id,w.id);
  assert.deepEqual(completion.data.health,health);
  assert.deepEqual(completion.data.totals,{sets:2,reps:18,volume_kg:270,cardio_min:0});
  assert.equal(completion.data.duration_min,10);
  assert.equal(events(done,{...done,active:null}).length,0);
  assert.equal(events(initial,saved).length,0);
  assert.equal(events(saved,copy(saved)).length,0);
  const mapped=bridge.prepare(initial,saved,raw,catalogue).state.workouts.find(x=>x.id===w.id);
  assert.equal(mapped.id,completion.data.workout_id);
  assert.deepEqual(mapped.health,completion.data.health);
});
