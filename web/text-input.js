/* Full-value commands preserve mobile IME, paste and Unicode. Lua owns edit identity. */
(() => {
  const form=document.getElementById('name-form'), input=document.getElementById('name-value');
  const error=document.getElementById('name-error'), reopen=document.getElementById('name-reopen');
  let state=null, fallbackId=null, composing=false, seq=0, ack=0;
  function send(message) {
    if(!window.Module || typeof Module.FS_createDataFile!=='function' || seq-ack>=32) {
      error.textContent='Espera un moment i torna-ho a provar.';return false;
    }
    const next=seq+1;
    try {Module.FS_createDataFile('/tmp','rodaui_'+next+'.json',new TextEncoder().encode(JSON.stringify(message)),true,true,true);seq=next;return true;}
    catch {error.textContent='No es pot enviar el text. Pots usar el teclat del joc.';return false;}
  }
  function text(action) {
    if(!state || composing)return;
    const value=Array.from(input.value).slice(0,state.maxChars||14).join('');
    if(send({type:'text',id:state.id,action,value})) {
      input.value=value;
      if(action==='replace')state.value=value;
    }
  }
  window.RodaUI={send,receive(message) {
    if(message.type==='ack'){ack=Math.max(ack,message.seq);return;}
    if(message.type!=='text'){window.dispatchEvent(new CustomEvent('roda-ui',{detail:message}));return;}
    if(!message.active){state=null;form.hidden=true;reopen.hidden=true;delete document.body.dataset.textMode;return;}
    const fresh=!state||state.id!==message.id;
    if(fresh){fallbackId=null;input.value=message.value;}
    else if(!composing && document.activeElement!==input)input.value=message.value;
    state=message;
    document.getElementById('name-title').textContent=message.title;
    error.textContent=message.error||'';
    form.hidden=fallbackId===message.id;
    reopen.hidden=!form.hidden;
    document.body.dataset.textMode=form.hidden?'grid':'form';
  }};
  form.addEventListener('submit',e=>{e.preventDefault();text('confirm');});
  input.addEventListener('compositionstart',()=>{composing=true;});
  input.addEventListener('compositionend',()=>{composing=false;text('replace');});
  input.addEventListener('input',()=>text('replace'));
  document.getElementById('name-cancel').addEventListener('click',()=>text('cancel'));
  document.getElementById('name-grid').addEventListener('click',()=>{
    text('replace');fallbackId=state.id;form.hidden=true;reopen.hidden=false;document.body.dataset.textMode='grid';document.getElementById('canvas').focus();
  });
  reopen.addEventListener('click',()=>{fallbackId=null;form.hidden=false;reopen.hidden=true;document.body.dataset.textMode='form';input.focus();});
  // SDL listens on window: HTML forms/chrome must not also move the player or confirm the grid.
  for(const event of ['keydown','keyup','keypress'])window.addEventListener(event,e=>{
    if(e.target.closest?.('#name-form,#hub-chrome,.hub-pin-backdrop,.hp-menu')) {
      e.stopImmediatePropagation();
      if(event==='keydown' && e.key==='Escape' && e.target.closest('#name-form')){e.preventDefault();text('cancel');}
    }
  },true);
})();
