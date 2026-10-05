/* RPG slots are characters, not hub identities. Old saves remain explicitly local. */
(() => {
  const hub=location.protocol+'//'+location.hostname+':8090';
  document.getElementById('jocs-link').href=hub+'/';
  let ready=false,wanted=null,active=null,serial=0,pending=null,hubProfile=null;
  const label=document.getElementById('owner-label'),error=document.getElementById('owner-error');
  const retry=document.getElementById('owner-retry'),cancel=document.getElementById('owner-cancel');
  function request(profile) {
    wanted=profile;
    if(!ready)return;
    const request=++serial;
    pending={request,profile};
    if(!window.RodaUI.send({type:'owner',id:profile?.id||null,request})){
      error.textContent='Espera que acabi de carregar el joc.';retry.hidden=false;cancel.hidden=false;
    }
  }
  window.addEventListener('roda-ui',e=>{
    const m=e.detail;
    if(m.type==='ready'){ready=true;request(wanted);const media=matchMedia('(prefers-reduced-motion: reduce)');const sync=()=>window.RodaUI.send({type:'motion',reduced:media.matches});sync();media.addEventListener('change',sync);return;}
    if(m.type!=='owner'||!pending||m.request!==pending.request)return;
    if(m.ok){active=pending.profile;label.textContent=active?'Partides: '+active.name:'Partides locals';showToggle();error.textContent='';retry.hidden=true;cancel.hidden=true;pending=null;}
    else{error.textContent=m.error;retry.hidden=false;cancel.hidden=false;}
  });
  retry.addEventListener('click',()=>request(wanted));
  cancel.addEventListener('click',()=>{wanted=active;pending=null;error.textContent='';retry.hidden=true;cancel.hidden=true;});
  // el botó diu què fa (abans sempre posava «Partides locals» i semblava l'estat actual): amb un jugador del hub
  // actiu passa a les partides locals, i des de les locals torna al jugador del hub
  const toggle=document.getElementById('local-games');
  function showToggle(){
    toggle.textContent=active?'Usar partides locals':hubProfile?'Usar partides de '+hubProfile.name:'Partides locals';
    toggle.disabled=!active&&!hubProfile;
  }
  toggle.addEventListener('click',()=>request(active?null:hubProfile));
  const fromHub=profile=>{hubProfile=profile||null;showToggle();request(profile);};
  const script=document.createElement('script');script.src=hub+'/vendor/hub-perfil.js';
  script.onload=()=>window.HubPerfil.init({mount:document.getElementById('hub-profile'),onChange:fromHub,
    onSettings:async()=>{
      try{if(await window.RodaAdult.ensure())location.href='/editor/';}
      catch(e){error.textContent=e.message;}
    }});
  script.onerror=()=>{error.textContent='Hub no disponible. Les partides locals continuen disponibles.';};
  document.head.append(script);
})();
