/* love.js only copies the save directory to IndexedDB on beforeunload, which mobile browsers often skip.
   Flush after every game save, when the tab is hidden and periodically; syncfs only writes changed files. */
(() => {
  let Module=null,running=false,again=false,last=0;
  function flush() {
    if(!Module || typeof Module.FS_syncfs!=='function')return;
    if(running){again=true;return;}
    running=true;again=false;
    try{
      Module.FS_syncfs(false,err=>{
        running=false;last=Date.now();
        if(err)console.warn('rodapersist: sync failed');
        if(again)flush();
      });
    }catch{running=false;console.warn('rodapersist: sync unavailable');}
  }
  window.RodaPersist={setup(m){Module=m;},flush};
  window.addEventListener('roda-ui',e=>{if(e.detail && e.detail.type==='saved')flush();});
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')flush();});
  window.addEventListener('pagehide',flush);
  setInterval(()=>{if(Date.now()-last>=20000)flush();},20000);
})();
