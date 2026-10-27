/* Shared-document adapter for the native client. Runs in JavaScriptCore (no WebView)
 * and in Node regression tests. The original server document is always retained;
 * only fields actually edited in the native projection are written back. */
var GymSyncBridge = (() => {
  const clone = x => x === undefined ? undefined : JSON.parse(JSON.stringify(x));
  const list = x => Array.isArray(x) ? x : [];
  const map = x => x && typeof x === 'object' && !Array.isArray(x) ? x : {};
  const canonical = x => Array.isArray(x) ? x.map(canonical) : x && typeof x === 'object'
    ? Object.fromEntries(Object.keys(x).sort().filter(k => x[k] != null).map(k => [k, canonical(x[k])])) : x;
  const same = (a, b) => JSON.stringify(canonical(a == null ? null : a)) === JSON.stringify(canonical(b == null ? null : b));
  // Stable identifiers for existing web IDs, which need not be UUIDs. Never written over web IDs.
  function uuid(key) {
    if (/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(String(key))) return String(key).toUpperCase();
    let hex = '';
    for (let seed = 0; seed < 4; seed++) {
      let h = (2166136261 ^ (seed * 2654435761)) >>> 0;
      for (const c of String(key)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619) >>> 0; }
      hex += h.toString(16).padStart(8, '0');
    }
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-5${hex.slice(13,16)}-a${hex.slice(17,20)}-${hex.slice(20)}`.toUpperCase();
  }
  const day = seconds => {
    const d = new Date(seconds * 1000);
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  };
  const date = d => new Date(`${d}T12:00:00`).getTime() / 1000;
  const fields = {neck:'颈围',shoulders:'肩围',chest:'胸围',waist:'腰围',hips:'臀围',abdomen:'腹围',
    upperArmLeft:'左上臂围',upperArmRight:'右上臂围',forearmLeft:'左前臂围',forearmRight:'右前臂围',
    wristLeft:'左腕围',wristRight:'右腕围',thighLeft:'左大腿围',thighRight:'右大腿围',
    calfLeft:'左小腿围',calfRight:'右小腿围',ankleLeft:'左踝围',ankleRight:'右踝围'};
  function projection(s, catalogue = {}) {
    const kg = s.unit === 'lb' ? 0.45359237 : 1;
    const speed = s.speedUnit === 'mph' ? 1.609344 : 1;
    const name = id => list(s.customEx).find(e => String(e.id) === String(id))?.n || catalogue[id]?.name || String(id);
    const mode = e => e.mode || e.target?.mode || (e.min != null || catalogue[e.id]?.mode === 'cardio' ? 'cardio' : e.sec != null ? 'time' : catalogue[e.id]?.mode || 'reps');
    const slots = (entries, parent, workout) => {
      const seen = {};
      return list(entries).map(e => {
        const n = seen[e.id] || 0; seen[e.id] = n + 1;
        const id = uuid(e._nativeId || `${parent}/exercise/${e.id}/${n}`);
        const common = {id, exerciseId:String(e.id), name:name(e.id), mode:mode(e), note:e.note || null};
        if (!workout) return {...common, setCount:Number(e.sets) || 3, reps:Number(e.reps) || 8,
          weight:e.weight == null ? null : e.weight * kg, minutes:e.min ?? null, speed:e.speed == null ? null : e.speed * speed,
          incline:e.incline ?? null, seconds:e.sec ?? null};
        return {...common, routineId:e.rid ? uuid(e.rid) : null, notePinned:e.notePinned ?? null,
          noProgression:e.noProg ?? null, restSeconds:e.restSec ?? null,
          sets:list(e.sets).map((v,i) => ({id:uuid(v._nativeId || `${id}/set/${i}`), weight:(v.w || 0)*kg,
            reps:v.r || 0, done:v.done === true, rir:v.rir ?? null, minutes:v.min ?? null,
            speed:v.speed == null ? null : v.speed * speed, incline:v.incline ?? null, seconds:v.sec ?? null,
            completedAt:v.at == null ? null : v.at / 1000}))};
      });
    };
    const custom = Object.fromEntries(list(s.customMeasurements).map(m => [m.id, m.name]));
    const profile = list(s.equipProfiles).find(p => p.id === s.activeEquipId);
    return {
      routines:list(s.routines).map(r => ({id:uuid(r.id),name:r.name || '',exercises:slots(r.ex,r.id,false)})),
      week:Array.from({length:7},(_,i) => ({day:i+1,routineIds:[].concat(s.week?.[String((i+1)%7)] || []).map(uuid)})),
      workouts:list(s.workouts).map(w => ({id:uuid(w.id || `${w.d}|${w.start}`),name:w.name || '训练',
        startedAt:w.start ? w.start/1000 : date(w.d),finishedAt:w.end ? w.end/1000 : date(w.d),health:w.health ?? null,
        exercises:slots(w.entries,w.id || `${w.d}|${w.start}`,true),note:w.note || null,noProgression:w.noProg ?? null})),
      weighIns:list(s.bodyweight).map(w => ({id:uuid(`weight/${w.d}`),date:date(w.d),kilograms:w.w*kg,
        bodyFatPercent:list(s.measurements).find(m=>m.d===w.d)?.bodyFat ?? null})),
      bodyMeasurements:list(s.measurements).map(m => ({id:uuid(`measurement/${m.d}`),date:date(m.d),bodyFatPercent:m.bodyFat ?? null,
        centimeters:Object.fromEntries([...Object.entries(fields).filter(([k])=>m[k]!=null).map(([k,v])=>[v,m[k]]),
          ...Object.entries(map(m.other)).filter(([,v])=>v!=null).map(([k,v])=>[custom[k] || k,v])])})),
      targetKg:s.targetW == null ? null : s.targetW*kg, restSeconds:s.restSec ?? 90,
      ownedEquipment:profile?.equipment || [],
      workoutPreferences:{layout:['cards','list','compact'].includes(s.workoutView)?s.workoutView:'cards',
        media:['full','mini','off'].includes(s.gifSize)?s.gifSize:'full',sound:s.sound !== false,haptics:s.vibrateOnSilent !== false,
        flash:s.timerFlash === true,keepAwake:s.keepAwake !== false,effort:['none','rir','rpe'].includes(s.effort)?s.effort:'rir'},
      dayPlan:Object.fromEntries(Object.entries(map(s.dayPlan)).map(([d,ids])=>[d,[].concat(ids || []).map(uuid)])),
      gymEquipment:list(s.gymEquipment).map(e=>({id:String(e.id),name:e.name || '',note:e.note || '',location:e.location || '',exerciseNames:list(e.exNames)}))
    };
  }
  // Three-way merge: independent edits combine. Concurrent changes to the same value,
  // including delete-versus-edit, stop visibly instead of choosing a silent winner.
  function merge(base, local, remote, path = '') {
    if (same(base, local)) return clone(remote);
    if (same(base, remote) || same(local, remote)) return clone(local);
    if (base == null || local == null || remote == null) throw new Error(`两端同时修改了 ${path}，未覆盖任何数据。请先在网页核对，再重新下载。`);
    if ([base,local,remote].every(Array.isArray)) {
      const key = v => v?.id ?? v?.day;
      if ([...base,...local,...remote].every(v => v && typeof v === 'object' && key(v)!=null)) {
        const bm=new Map(base.map(v=>[key(v),v])), lm=new Map(local.map(v=>[key(v),v])), rm=new Map(remote.map(v=>[key(v),v]));
        const order = same(base.map(key),local.map(key)) ? remote.map(key) : local.map(key);
        return [...new Set([...order,...remote.map(key),...base.map(key)])].map(k=>merge(bm.get(k),lm.get(k),rm.get(k),`${path}/${k}`)).filter(v=>v!=null);
      }
    } else if ([base,local,remote].every(v=>v && typeof v==='object' && !Array.isArray(v))) {
      const result = {};
      for (const k of new Set([...Object.keys(base),...Object.keys(local),...Object.keys(remote)])) {
        const v = merge(base[k],local[k],remote[k],`${path}/${k}`); if (v !== undefined) result[k]=v;
      }
      return result;
    }
    throw new Error(`两端同时修改了 ${path}，未覆盖任何数据。请先在网页核对，再重新下载。`);
  }
  const syncedKeys = ['routines','week','workouts','weighIns','bodyMeasurements','targetKg','restSeconds','ownedEquipment','workoutPreferences'];
  const pick = s => Object.fromEntries(syncedKeys.map(k=>[k,s[k]]));
  function prepare(base, local, raw, catalogue = {}) {
    const before=projection(raw,catalogue), after=merge(pick(base),pick(local),pick(before));
    const result=clone(raw), kg=raw.unit==='lb'?0.45359237:1, speed=raw.speedUnit==='mph'?1.609344:1;
    const update = (obj,a,b,native,web,convert=x=>x) => {
      if (!a || !same(a[native],b[native])) { if (b[native]==null) delete obj[web]; else obj[web]=convert(b[native]); }
    };
    function records(web, a, b, encode) {
      const byId=new Map(list(a).map((v,i)=>[v.id,{native:v,raw:list(web)[i]}]));
      return list(b).map(v=>{ const old=byId.get(v.id); return same(old?.native,v)?clone(old.raw):encode(clone(old?.raw || {}),old?.native,v); });
    }
    const routineWebId = id => list(result.routines).find(r=>uuid(r.id)===id)?.id || id;
    function exercise(e,a,b,isWorkout) {
      if (!a) e._nativeId=b.id;
      update(e,a,b,'exerciseId','id'); update(e,a,b,'note','note');
      if (!isWorkout) {
        for (const [n,w] of [['setCount','sets'],['reps','reps'],['mode','mode'],['minutes','min'],['seconds','sec'],['incline','incline']]) update(e,a,b,n,w);
        update(e,a,b,'weight','weight',v=>v/kg); update(e,a,b,'speed','speed',v=>v/speed);
      } else {
        update(e,a,b,'notePinned','notePinned'); update(e,a,b,'noProgression','noProg'); update(e,a,b,'restSeconds','restSec');
        update(e,a,b,'routineId','rid',routineWebId);
        if (!a) e.target={mode:b.mode || 'reps'};
        if (!same(a?.sets,b.sets)) e.sets=records(e.sets,a?.sets,b.sets,(s,old,v)=>{
          if (!old) s._nativeId=v.id;
          for (const [n,w] of [['reps','r'],['done','done'],['rir','rir'],['minutes','min'],['seconds','sec'],['incline','incline']]) update(s,old,v,n,w);
          update(s,old,v,'weight','w',v=>v/kg); update(s,old,v,'speed','speed',v=>v/speed); update(s,old,v,'completedAt','at',v=>v*1000);
          return s;
        });
      }
      return e;
    }
    if (!same(before.routines,after.routines)) result.routines=records(raw.routines,before.routines,after.routines,(r,a,b)=>{
      if (!a) r.id=b.id;
      update(r,a,b,'name','name');
      if (!same(a?.exercises,b.exercises)) r.ex=records(r.ex,a?.exercises,b.exercises,(e,x,y)=>exercise(e,x,y,false));
      return r;
    });
    if (!same(before.week,after.week)) {
      result.week={...map(raw.week)};
      for (const d of after.week) if (!same(d.routineIds,before.week.find(x=>x.day===d.day)?.routineIds)) result.week[String(d.day%7)]=d.routineIds.map(routineWebId);
    }
    if (!same(before.workouts,after.workouts)) result.workouts=records(raw.workouts,before.workouts,after.workouts,(w,a,b)=>{
      if (!a) { w.id=b.id; w.d=day(b.startedAt); w.prs=[]; }
      for (const [n,k] of [['name','name'],['note','note'],['noProgression','noProg'],['health','health']]) update(w,a,b,n,k);
      update(w,a,b,'startedAt','start',v=>v*1000); update(w,a,b,'finishedAt','end',v=>v*1000);
      if (!same(a?.exercises,b.exercises)) w.entries=records(w.entries,a?.exercises,b.exercises,(e,x,y)=>exercise(e,x,y,true));
      if (!a) { w.routineIds=[...new Set(b.exercises.map(e=>e.routineId).filter(Boolean))].map(routineWebId); w.routineId=w.routineIds[0] || null;
        w.vol=b.exercises.reduce((sum,e)=>sum+e.sets.filter(s=>s.done).reduce((v,s)=>v+s.weight/kg*s.reps,0),0); }
      return w;
    });
    if (!same(before.weighIns,after.weighIns)) result.bodyweight=records(raw.bodyweight,before.weighIns,after.weighIns,(w,a,b)=>{
      if (!a) w.d=day(b.date); update(w,a,b,'kilograms','w',v=>v/kg); update(w,a,b,'date','d',day); return w;
    });
    if (!same(before.bodyMeasurements,after.bodyMeasurements)) result.measurements=records(raw.measurements,before.bodyMeasurements,after.bodyMeasurements,(m,a,b)=>{
      if (!a) m.d=day(b.date); update(m,a,b,'date','d',day);
      update(m,a,b,'bodyFatPercent','bodyFat');
      for (const [key,label] of Object.entries(fields)) update(m,a?.centimeters,b.centimeters,label,key);
      for (const custom of list(raw.customMeasurements)) {
        if (!same(a?.centimeters?.[custom.name],b.centimeters[custom.name])) { m.other={...map(m.other)}; update(m.other,a?.centimeters,b.centimeters,custom.name,custom.id); }
      }
      // Older native archives used symmetric names. Retain those values explicitly on both sides.
      for (const [label,left,right] of [['上臂围','upperArmLeft','upperArmRight'],['大腿围','thighLeft','thighRight'],['小腿围','calfLeft','calfRight']]) {
        if (b.centimeters[label]!=null && !same(a?.centimeters?.[label],b.centimeters[label])) { m[left]=b.centimeters[label]; m[right]=b.centimeters[label]; }
      }
      return m;
    });
    for (const w of after.weighIns) {
      const old=before.weighIns.find(x=>x.id===w.id);
      if (same(old?.bodyFatPercent,w.bodyFatPercent)) continue;
      if (!Array.isArray(result.measurements)) result.measurements=[];
      let m=result.measurements.find(m=>m.d===day(w.date));
      if (!m && w.bodyFatPercent!=null) { m={d:day(w.date)}; result.measurements.push(m); }
      if (m) { if (w.bodyFatPercent==null) delete m.bodyFat; else m.bodyFat=w.bodyFatPercent; }
    }
    update(result,before,after,'targetKg','targetW',v=>v/kg); update(result,before,after,'restSeconds','restSec');
    for (const [n,w] of [['layout','workoutView'],['media','gifSize'],['sound','sound'],['haptics','vibrateOnSilent'],['flash','timerFlash'],['keepAwake','keepAwake'],['effort','effort']]) update(result,before.workoutPreferences,after.workoutPreferences,n,w);
    if (!same(before.ownedEquipment,after.ownedEquipment)) {
      result.equipProfiles=list(result.equipProfiles);
      let p=result.equipProfiles.find(p=>p.id===result.activeEquipId);
      if (!p) { p={id:'native-equipment',name:'我的器械',equipment:[],accV:1}; result.equipProfiles.push(p); result.activeEquipId=p.id; }
      p.equipment=after.ownedEquipment;
    }
    delete result.active;
    return {state:result,changed:!same(raw,result),snapshot:{...before,...after}};
  }
  return {projection,prepare,merge,uuid,fields,day};
})();
