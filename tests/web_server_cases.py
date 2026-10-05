"""Handler tests: no live server, provider or household data."""
import importlib.util, io, json, pathlib, tempfile, unittest
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('roda_server',ROOT/'tools/web_server.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
ORIGINAL_PUBLISH=m.run_publish
class ServerTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.patches=[]
  for name,value in [('run_publish',lambda:None),('private_home',lambda:{}),('npc_chat',None)]:
   if value is not None:
    p=patch.object(m,name,value);p.start();self.addCleanup(p.stop)
  p=patch.object(m.urllib.request,'urlopen',side_effect=OSError('network disabled in tests'));p.start();self.addCleanup(p.stop)
  for key,val in {'ZONES':self.tmp.name,'HISTORY':self.tmp.name+'/.history','NPCS':self.tmp.name+'/npcs.json','MAP_EDITS':self.tmp.name+'/map-edits.json'}.items():
   p=patch.object(m,key,val);p.start();self.addCleanup(p.stop)
 def request(self,method,path,body=None,headers=None,addr='127.0.0.1'):
  h=object.__new__(m.Handler);h.path=path;h.command=method;h.client_address=(addr,50000)
  raw=json.dumps(body).encode() if body is not None else b''
  h.headers={'Host':'127.0.0.1:8102','Origin':'http://127.0.0.1:8102','Content-Type':'application/json','X-Roda-Request':'1','Content-Length':str(len(raw)),**(headers or {})}
  h.rfile=io.BytesIO(raw);h.responses=[];h.response_headers={}
  def respond(obj,code=200,**kw):
   h.responses.append((code,obj))
   if getattr(h,'document_etag',None):h.response_headers['ETag']=h.document_etag
  h.send_json=respond
  h.send_header=lambda k,v:h.response_headers.update({k:v})
  getattr(h,'do_'+method)();return h
 def test_mutations_and_private_reads_require_auth(self):
  for method,path,body in [('PUT','/api/npcs',[]),('PUT','/api/map_edits',{'cells':{}}),('PUT','/api/zones/test',{}),('DELETE','/api/zones/test',None),('POST','/api/publish',{}),('POST','/api/procgen',{}),('POST','/api/sat2pixel',{}),('GET','/api/npcs',None)]:
   with self.subTest(path=path): self.assertIn(self.request(method,path,body).responses[-1][0],(401,403))
  self.assertFalse(pathlib.Path(m.NPCS).exists())
 def test_private_home_without_pin_only_from_lan(self):
  self.assertEqual(self.request('POST','/api/private_home',{}).responses[-1][0],200)
  self.assertEqual(self.request('POST','/api/private_home',{},addr='8.8.8.8').responses[-1][0],403)
 def test_chat_rate_limit(self):
  m.chat_hits.clear()
  with patch.object(m,'CHAT_PER_MIN',3):
   self.assertEqual([m.chat_allowed('10.0.0.9') for _ in range(4)],[True,True,True,False])
   self.assertTrue(m.chat_allowed('10.0.0.10'))
  m.chat_hits.clear()
 def test_body_boundaries(self):
  for n,code in [('-1',400),('wat',400),('99999999',413)]:
   h=self.request('POST','/api/npc_chat',{}, {'Content-Length':n});self.assertEqual(h.responses[-1][0],code)
 def test_map_bounds(self):
  self.assertIsNotNone(m.validate_map_edits({'cells':{'9999,9999':{'ground':None}}}))
 def test_malformed_chat(self):
  for body in [[],{'npc':[]},{'npc':{'say':3}},{'history':3}]:
   self.assertEqual(self.request('POST','/api/npc_chat',body).responses[-1][0],400)
 def test_origin(self):
  self.assertEqual(self.request('POST','/api/npc_chat',{}, {'Origin':'http://evil.example'}).responses[-1][0],403)
 def test_login_expiry_and_hub_failure(self):
  m.auth_attempts.clear();m.sessions.clear()
  with patch.object(m,'verify_adult',return_value=False):
   self.assertEqual(self.request('POST','/api/adult-check',{'pin':'1234'}).responses[-1][0],401)
  with patch.object(m,'verify_adult',side_effect=m.APIError(503,'offline')):
   self.assertEqual(self.request('POST','/api/adult-check',{'pin':'1234'}).responses[-1][0],503)
  with patch.object(m,'verify_adult',return_value=True):
   login=self.request('POST','/api/adult-check',{'pin':'1234'})
   self.assertEqual(login.responses[-1][0],200)
   cookie=login.session_cookie.split(';')[0]
  self.assertEqual(self.request('GET','/api/npcs',headers={'Cookie':cookie}).responses[-1][0],200)
  for k in m.sessions:m.sessions[k]=0
  self.assertEqual(self.request('GET','/api/npcs',headers={'Cookie':cookie}).responses[-1][0],401)
 def test_simple_post_and_host_are_rejected(self):
  self.assertEqual(self.request('POST','/api/npc_chat',{}, {'X-Roda-Request':''}).responses[-1][0],403)
  self.assertEqual(self.request('POST','/api/npc_chat',{}, {'Host':'evil.example','Origin':'http://evil.example'}).responses[-1][0],403)
 def test_validation_types(self):
  for v in [None,[],{'id':'xx','x':True,'y':0,'w':4,'h':4},{'id':'xx','x':0,'y':0,'w':4,'h':4,'interiors':[]}]:
   self.assertIsNotNone(m.validate_zone(v))
  self.assertIsNotNone(m.validate_npcs([{'id':'xx','x':0,'y':0,'say':5}]))
 def test_revisions_and_concurrent_writes(self):
  import concurrent.futures,time
  m.sessions['fixture']=time.monotonic()+60
  auth={'Cookie':'roda_adult=fixture'}
  self.assertEqual(self.request('PUT','/api/npcs',[],auth).responses[-1][0],428)
  first=self.request('GET','/api/npcs',headers=auth)
  rev=first.response_headers['ETag']
  headers={**auth,'If-Match':rev}
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
   futures=[pool.submit(self.request,'PUT','/api/npcs',[],headers) for _ in range(2)]
   codes=sorted(f.result().responses[-1][0] for f in futures)
  self.assertEqual(codes,[200,409])
  latest=self.request('GET','/api/npcs',headers=auth).response_headers['ETag']
  self.assertNotEqual(rev,latest)
  self.assertEqual(self.request('PUT','/api/npcs',[],{**auth,'If-Match':latest}).responses[-1][0],200)
  self.assertTrue(list(pathlib.Path(m.HISTORY).glob('*.json')))
 def test_corrupt_editor_document_not_overwritten(self):
  import time
  m.sessions['fixture']=time.monotonic()+60
  pathlib.Path(m.NPCS).write_text('{broken')
  response=self.request('PUT','/api/npcs',[],{'Cookie':'roda_adult=fixture','If-Match':'"missing"'})
  self.assertIn(response.responses[-1][0],(409,503))
  self.assertEqual(pathlib.Path(m.NPCS).read_text(),'{broken')
 def test_private_npc_metadata_never_reaches_provider(self):
  with patch.object(m.urllib.request,'urlopen') as provider:
   result=m.npc_chat({'npc':{'name':'Private name','persona':'private home'},'ask':'Hola!'})
   self.assertFalse(result['ai']);provider.assert_not_called()
 def test_provider_failures_use_local_reply(self):
  pathlib.Path(m.NPCS).write_text(json.dumps([{'id':'public_npc','name':'Veí','ai':True,'say':['Bon dia!'],'persona':'Veí del poble'}]))
  req={'npc':{'id':'public_npc'},'ask':'Hola!'}
  for payload in [b'',b'{}',b'{bad',b'{"text":"[]"}']:
   class Response:
    def read(self,*args):return payload
    def __enter__(self):return self
    def __exit__(self,*args):pass
   with patch.object(m.urllib.request,'urlopen',return_value=Response()):
    self.assertEqual(m.npc_chat(req)['reply'],'Bon dia!')
  with patch.object(m.urllib.request,'urlopen',side_effect=TimeoutError()):
   self.assertFalse(m.npc_chat(req)['ai'])
 def test_failed_publication_does_not_touch_active_map(self):
  root=pathlib.Path(self.tmp.name)/'project';(root/'maps/runtime').mkdir(parents=True);(root/'build').mkdir()
  marker=root/'maps/runtime/marker';marker.write_text('active')
  class Failed:
   returncode=1;stdout='';stderr='fixture failure'
  def command(cmd,cwd,**kw):
   (pathlib.Path(cwd)/'maps/runtime/marker').write_text('changed by compiler')
   return Failed()
  # setUp stubs public publish calls; use the original function for this isolated test.
  with patch.object(m,'ROOT',str(root)),patch.object(m.subprocess,'run',side_effect=command):
   ORIGINAL_PUBLISH()
  self.assertEqual(marker.read_text(),'active')
  self.assertFalse(m.publish_state['ok'])
 def test_zone_objects_and_relative_polygon(self):
  base={'id':'test','x':0,'y':0,'w':4,'h':4}
  for extra in [{'objects':[{'type':'npc','x':99,'y':0}]},{'objects':{}},{'poly':[[0,0],[5,0],[0,4]]}]:
   self.assertIsNotNone(m.validate_zone({**base,**extra}))
  self.assertIsNone(m.validate_zone({**base,'poly':[[0,0],[4,0],[0,4]]}))
if __name__=='__main__':unittest.main()
