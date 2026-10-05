/* Shared PIN UI; authorization is a short HttpOnly session checked by the RPG server. */
(() => {
  let pending;
  window.RodaAdult = {
    ensure() {
      if (pending) return pending;
      pending = (async () => {
        if (!window.hubProvesPin) {
          await new Promise((resolve,reject) => {
            const script=document.createElement('script');
            script.src=location.protocol+'//'+location.hostname+':8090/vendor/hub-pin.js';
            script.onload=resolve;script.onerror=()=>reject(new Error('No es pot carregar el PIN del hub'));
            document.head.append(script);
          });
        }
        let pin;
        const accepted=await window.hubProvesPin({title:'Editor d’adults',onVerified:v=>{pin=v;}});
        if (!accepted || !pin) return false;
        const response=await fetch('/api/adult-check',{method:'POST',headers:{'Content-Type':'application/json','X-Roda-Request':'1'},
          body:JSON.stringify({pin}),signal:AbortSignal.timeout(7000)});
        pin=null;
        if(!response.ok)throw new Error('No es pot obrir la sessió adulta. Torna-ho a provar.');
        return true;
      })().finally(()=>{pending=null;});
      return pending;
    }
  };
})();
