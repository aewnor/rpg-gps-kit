"""Real HTTP boundary smoke with temporary documents and a synthetic adult verifier."""
import http.client, importlib.util, json, pathlib, tempfile, threading, unittest
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('server', pathlib.Path(__file__).resolve().parents[1]/'tools/web_server.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class HTTPTests(unittest.TestCase):
 def test_http_contract(self):
  with tempfile.TemporaryDirectory() as directory:
   root=pathlib.Path(directory)
   (root/'build/web').mkdir(parents=True)
   (root/'build/web/index.html').write_text('<!doctype html>fixture')
   (root/'maps/runtime/overworld').mkdir(parents=True)
   (root/'maps/runtime/overworld/index.lua').write_text('return {width=1600,height=1600}')
   (root/'releases/fixture').mkdir(parents=True)
   (root/'releases/fixture/love.wasm').write_bytes(b'fixture')
   with patch.object(m,'ROOT',directory), patch.object(m,'NPCS',str(root/'npcs.json')), patch.object(m,'HISTORY',str(root/'history')), patch.object(m,'verify_adult',return_value=True):
    server=m.ThreadingHTTPServer(('127.0.0.1',0),m.Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
     def request(method,path,body=None,headers=None):
      conn=http.client.HTTPConnection(*server.server_address,timeout=5)
      raw=json.dumps(body) if body is not None else None
      conn.request(method,path,raw,{'Content-Type':'application/json','X-Roda-Request':'1',**(headers or {})})
      r=conn.getresponse();result=(r.status,dict(r.getheaders()),r.read());conn.close();return result
     self.assertEqual(request('GET','/api/npcs')[0],401)
     self.assertEqual(request('POST','/api/npc_chat',{}, {'Origin':'http://evil.example'})[0],403)
     status,headers,_=request('POST','/api/adult-check',{'pin':'1234'})
     self.assertEqual(status,200);self.assertIn('HttpOnly',headers['Set-Cookie'])
     auth={'Cookie':headers['Set-Cookie'].split(';')[0]}
     status,headers,_=request('GET','/api/npcs',headers=auth)
     self.assertEqual(status,200);auth['If-Match']=headers['ETag']
     self.assertEqual(request('PUT','/api/npcs',[],auth)[0],200)
     self.assertEqual(request('PUT','/api/npcs',[],auth)[0],409)
     self.assertEqual(request('GET','/')[1]['Cache-Control'],'no-cache')
     status,headers,_=request('GET','/releases/fixture/love.wasm')
     self.assertEqual(status,200);self.assertIn('immutable',headers['Cache-Control'])
     self.assertEqual(headers['Content-type'],'application/wasm')
     self.assertEqual(request('GET','/missing')[0],404)
    finally:
     server.shutdown();server.server_close();thread.join()

if __name__=='__main__': unittest.main()
