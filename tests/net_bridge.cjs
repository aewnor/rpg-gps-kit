const vm=require('vm'),fs=require('fs'),assert=require('assert');
let write;const files=new Map(),pending=[];
const Module={FS_createDevice(a,b,c,d){write=d;},FS_unlink(p){files.delete(p);},FS_createDataFile(dir,name,data){files.set(dir+'/'+name,new TextDecoder().decode(data));}};
const context={window:{},AbortController,TextEncoder,TextDecoder,Uint8Array,console,setTimeout,clearTimeout,
 fetch:(url,opts)=>new Promise(resolve=>pending.push({resolve,signal:opts.signal}))};
vm.runInNewContext(fs.readFileSync('web/net-bridge.js','utf8'),context);context.window.RodaNet.setup(Module);
function send(v){for(const b of new TextEncoder().encode(JSON.stringify(v)+'\n'))write(b);}
(async()=>{
 for(let i=0;i<100;i++){
  const id=i+'_1';send({id,path:'/api/npc_chat',body:{}});send({id,cmd:'cancel'});
  const p=pending.shift();assert(p.signal.aborted);p.resolve({ok:true,text:async()=>'{"reply":"late"}'});
  await new Promise(r=>setImmediate(r));assert.equal(files.size,0);
 }
 send({id:'200_1',path:'/api/npc_chat',body:{}});pending.shift().resolve({ok:false,status:429});
 await new Promise(r=>setImmediate(r));assert(JSON.parse(files.get('/tmp/rodanet_200_1.json')).error);
 send({id:'200_1',cmd:'cancel'});assert.equal(files.size,0);
 console.log('net_bridge: OK (100 late cancellations, 429, cleanup)');
})().catch(e=>{console.error(e);process.exit(1)});
