#!/usr/bin/env node
/* Element 10 — headless prototype evidence harness.
   Runs interaction / mutator / persisted-state / boundary evidence WITHOUT a browser.
   Render (screenshot) evidence is the ONLY class this cannot produce.

   Usage:  node e10_harness.js <path-to-08-product-workspace.html> [scenarioFile.js]
   Exit 0 = all scenarios pass. Exit 1 = any failure (CI-usable).

   Scenario file exports: module.exports = async (ctx) => { ... }
   ctx = { w, d, pf, S, $, setVal, clickReal, tick, ok, info }
     ok(name, condition, detail)  — records PASS/FAIL
     info(name, detail)           — records context
   Everything is driven through REAL DOM events (mousedown→mouseup→click,
   input events) so in-flight-interaction defects reproduce, not synthetic calls.
*/
const fs=require('fs'), path=require('path');
const {JSDOM}=require('jsdom');

const file=process.argv[2], scen=process.argv[3];
if(!file){console.error('usage: node e10_harness.js <html> [scenario.js]');process.exit(2);}

const raw=fs.readFileSync(file,'utf8');
// inline the css if present next to the html (keeps jsdom quiet; irrelevant to logic)
const cssPath=path.join(path.dirname(file),'e10.css');
const html=fs.existsSync(cssPath)
  ? raw.replace(/<link[^>]*e10\.css[^>]*>/,'<style>'+fs.readFileSync(cssPath,'utf8')+'</style>')
  : raw.replace(/<link[^>]*e10\.css[^>]*>/,'');

const errors=[];
const dom=new JSDOM(html,{runScripts:'dangerously',url:'https://prototype.local/08.html',
  pretendToBeVisual:true,
  beforeParse(w){
    w.requestAnimationFrame=cb=>setTimeout(cb,0);
    w.cancelAnimationFrame=()=>{};
    w.scrollTo=()=>{};
    w.addEventListener('error',e=>errors.push('window.onerror: '+(e.message||e.error)));
  }});
const w=dom.window, d=w.document;

const R=[];
const ok=(n,c,x)=>R.push([c?'PASS':'FAIL',n,String(x==null?'':x)]);
const info=(n,x)=>R.push(['INFO',n,String(x==null?'':x)]);
const $=s=>d.querySelector(s);
const setVal=(el,v)=>{if(!el)throw new Error('setVal: element not found');el.value=v;el.dispatchEvent(new w.Event('input',{bubbles:true}));};
const clickReal=el=>{if(!el)throw new Error('clickReal: element not found');
  el.dispatchEvent(new w.MouseEvent('mousedown',{bubbles:true,cancelable:true}));
  el.dispatchEvent(new w.MouseEvent('mouseup',{bubbles:true}));
  el.dispatchEvent(new w.MouseEvent('click',{bubbles:true}));};
const tick=(ms=25)=>new Promise(r=>setTimeout(r,ms));

setTimeout(async()=>{
  const boot=Date.now();
  try{
    const pf=w.__pf;
    if(!pf){throw new Error('window.__pf missing — the prototype did not boot (parse error or hang?)');}
    info('boot','ok in '+(Date.now()-boot)+'ms; harness surface exposes '+Object.keys(pf).length+' members');
    if(scen){
      const run=require(path.resolve(scen));
      await run({w,d,pf,S:pf.S,$,setVal,clickReal,tick,ok,info});
    }else{
      // default smoke: prove the build boots, routes, and its guards are live
      ok('boots and exposes harness', !!pf.S && typeof pf.canWrite==='function');
      w.location.hash='#products'; w.route&&w.route(); await tick();
      ok('renders products route', /Products/.test(($('#app')||d.body).textContent));
      const scan=pf.scanCardsOff&&pf.scanCardsOff();
      info('cards-off scan (current org)', scan?JSON.stringify(scan.hits):'n/a');
    }
  }catch(e){ R.push(['ERROR','harness',e.stack.split('\n').slice(0,3).join(' | ')]); }
  if(errors.length) errors.forEach(e=>R.push(['ERROR','page',e]));
  R.forEach(r=>console.log(r[0].padEnd(6),r[1].padEnd(52),r[2]));
  const bad=R.filter(r=>r[0]==='FAIL'||r[0]==='ERROR').length;
  console.log('---',R.length,'records,',bad,'failing');
  process.exit(bad?1:0);
},700);
