/* Requests are cancellable; a late result may never recreate a cancelled response file. */
(() => {
  window.RodaNet={setup(Module) {
    const active=new Map();let bytes=[];
    const file=id=>'rodanet_'+id+'.json';
    const remove=id=>{try{Module.FS_unlink('/tmp/'+file(id));}catch{}};
    async function receive(raw) {
      let req;try{req=JSON.parse(raw);}catch{return;}
      if(!req || !/^[0-9]+_[0-9]+$/.test(req.id))return;
      if(req.cmd==='cancel'){
        const request=active.get(req.id);active.delete(req.id);request?.abort();remove(req.id);return;
      }
      if(!['/api/npc_chat','/api/private_home','/api/config','/api/sync/pull','/api/sync/push','/api/sync/delete'].includes(req.path))return;
      const controller=new AbortController();
      active.set(req.id,controller);
      const timer=setTimeout(()=>controller.abort(),12000);
      let text;
      try {
        if(active.size>8)throw new Error('busy');
        const r=await fetch(req.path,{method:'POST',headers:{'Content-Type':'application/json','X-Roda-Request':'1'},body:JSON.stringify(req.body),signal:controller.signal});
        text=r.ok?await r.text():JSON.stringify({error:'http '+r.status});
        if(text.length>1048576)throw new Error('response too large');
      }catch{text=JSON.stringify({error:'sense connexió'});}
      finally{clearTimeout(timer);}
      if(active.get(req.id)!==controller)return;
      active.delete(req.id);remove(req.id);
      try{Module.FS_createDataFile('/tmp',file(req.id),new TextEncoder().encode(text),true,true,true);}
      catch{console.warn('rodanet: response unavailable');}
    }
    Module.FS_createDevice('/dev','rodanet',()=>null,c=>{
      if(c===null||c===undefined)return;
      if(c===10){const raw=new TextDecoder().decode(new Uint8Array(bytes));bytes=[];receive(raw);}
      else if(bytes.length<1048576)bytes.push(c);   // perfils sincronitzats: fins a 1 MB
    });
  }};
})();
