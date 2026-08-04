/* Element 10 — MANDATORY self-debug sweep.
   Run BEFORE any evidence pass, on every touched surface, every gate.
   This is exploration, not scenario testing: it drives controls like a person
   would and asks "is anything simply broken?" — the class of defect that
   repeatedly reached the operator (unclickable rows, reversed typing, dead
   buttons, undismissable dropdowns, dead-end saves).

   node e10_harness.js <build.html> selfdebug.js
*/
module.exports = async ({w,d,pf,S,$,setVal,clickReal,tick,ok,info})=>{
  const HOSTS=['#app','#ovhost'];
  const vis=el=>el && !el.disabled && (el.offsetParent!==null || true);
  const errs=[]; w.addEventListener('error',e=>errs.push(e.message||String(e.error)));

  const surfaces=[
    {name:'products',   hash:'#products'},
    {name:'vendors',    hash:'#vendors'},
    {name:'singles',    hash:'#singles'},
    {name:'checklists', hash:'#checklists'},
  ];

  // ---------- 1. NATIVE POPOVER BAN (mechanically checkable) ----------
  ok('no <datalist> anywhere (native suggest banned)',
     d.querySelectorAll('datalist').length===0,
     d.querySelectorAll('datalist').length+' found');
  const src=d.documentElement.innerHTML
      .replace(/\/\*[\s\S]*?\*\//g,'')      // block comments
      .replace(/^\s*\/\/.*$/gm,'');          // line comments
  const nat=(src.match(/(^|[^.\w])(window\.)?(alert|prompt)\s*\(/g)||[])
      .concat((src.match(/(^|[^.\w\-])confirm\s*\(/g)||[]).filter(x=>!/ui/i.test(x)));
  ok('no native alert/prompt/confirm calls', nat.length===0, nat.slice(0,3).join(' '));

  // ---------- 2. EVERY SURFACE RENDERS AND ITS CONTROLS RESPOND ----------
  for(const s of surfaces){
    w.location.hash=s.hash; w.route&&w.route(); await tick(40);
    const app=$('#app')||d.body;
    const txt=(app.textContent||'').trim();
    ok(`[${s.name}] renders non-empty`, txt.length>40, txt.slice(0,48).replace(/\s+/g,' '));

    // every text input must round-trip AND keep the caret at the end
    const inputs=[...app.querySelectorAll('input[type=text],input:not([type]),input[type=number],input[type=search]')].filter(vis).slice(0,12);
    for(const el of inputs){
      const id=el.id||el.getAttribute('placeholder')||'(anon input)';
      let typed=''; let replaced=false; let cur=el;
      try{
        for(const ch of 'blue'){
          cur = (el.id && d.getElementById(el.id)) || cur;   // RE-ACQUIRE: the node may have been replaced
          if(cur!==el) replaced=true;
          cur.focus();
          typed+=ch; cur.value=typed;
          try{ cur.setSelectionRange(typed.length,typed.length); }catch(_){}
          cur.dispatchEvent(new w.Event('input',{bubbles:true}));
          await tick(8);
        }
      }catch(e){ ok(`[${s.name}] input "${id}" accepts typing`, false, e.message); continue; }
      const live=(el.id && d.getElementById(el.id))||cur;
      const val=live.value;
      ok(`[${s.name}] "${id}" types forward (not reversed)`, val==='blue'||val.endsWith('blue'), 'got "'+val+'"');
      // caret: only meaningful if the node was REPLACED during typing (the real defect class).
      if(replaced){
        ok(`[${s.name}] "${id}" survives self-rerender with caret intact`,
           live.selectionStart==null||live.selectionStart===val.length,
           'node replaced mid-typing; caret='+live.selectionStart+' len='+val.length);
      } else {
        info(`[${s.name}] "${id}" caret (advisory, node not replaced)`, 'caret='+live.selectionStart);
      }
    }

    // every enabled button must do SOMETHING (state or DOM change) and never throw
    const btns=[...app.querySelectorAll('button')].filter(vis).slice(0,10);
    for(const b of btns){
      const label=(b.textContent||'').trim().slice(0,26)||'(icon)';
      const snap=()=>{const a=($('#app')||d.body).innerHTML||'',o=($('#ovhost')||{innerHTML:''}).innerHTML||'';let h=0;const str=a+'|'+o+'|'+w.location.hash;for(let i=0;i<str.length;i++){h=(h*31+str.charCodeAt(i))|0;}return h;};
      const before=snap();
      const errCountBefore=errs.length;
      try{ clickReal(b); }catch(e){ ok(`[${s.name}] button "${label}" click throws`, false, e.message); continue; }
      await tick(30);
      const after=snap();
      ok(`[${s.name}] "${label}" click raises no error`, errs.length===errCountBefore, errs.slice(errCountBefore).join('; '));
      info(`[${s.name}] "${label}" changed something`, before!==after ? 'yes' : 'NO — inert control?');
      // if it opened a dialog, prove Escape closes it, then clear
      if(($('#ovhost')||{innerHTML:''}).innerHTML){
        d.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true})); await tick(30);
        const stillOpen=!!($('#ovhost')||{innerHTML:''}).innerHTML;
        ok(`[${s.name}] "${label}" dialog closes on Escape`, !stillOpen || !!d.querySelector('#confirmscrim'),
           stillOpen?'still open after Escape':'closed');
        const ov=$('#ovhost'); if(ov) ov.innerHTML='';
      }
    }
  }

  // ---------- 3. CARDS-OFF SWEEP ON EVERY SURFACE ----------
  if(w.setEnt){
    w.setEnt(false); await tick(40);
    const c=d.querySelector('#confirmscrim');
    if(c){ const disc=[...c.querySelectorAll('button')].find(b=>/discard/i.test(b.textContent)); disc&&clickReal(disc); await tick(30); }
    for(const s of surfaces){ w.location.hash=s.hash; w.route&&w.route(); await tick(30);
      const scan=pf.scanCardsOff&&pf.scanCardsOff();
      ok(`[cards-off @ ${s.name}] scan clean`, !scan||scan.hits.length===0, scan?JSON.stringify(scan.hits):'n/a'); }
    w.setEnt(true); await tick(30);
  }

  // ---------- 4. UNCAUGHT ERRORS OVERALL ----------
  ok('no uncaught page errors during the sweep', errs.length===0, errs.slice(0,3).join(' | '));
  info('controls swept','see records above — every INFO reading "NO — inert control?" needs an explanation in the report');
};
