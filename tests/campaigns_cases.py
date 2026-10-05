"""Campañas de misiones (tools/campaigns.py) y su API (/api/campaigns de tools/web_server.py).

python3 tests/campaigns_cases.py — sin red: la IA se simula con un /api/groq falso.
"""
import copy, http.client, importlib.util, json, pathlib, shutil, sys, tempfile, threading, unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import campaigns as C

spec = importlib.util.spec_from_file_location('server', ROOT / 'tools/web_server.py')
server = importlib.util.module_from_spec(spec); spec.loader.exec_module(server)

REF = C.reference()
DATA = C.load()


def mission(mid, **kw):
    m = {'id': mid, 'cat': 'nav', 'title': 'Prova', 'xp': 20, 'coins': 2, 'intro': ['Hola!'],
         'steps': [{'type': 'goto', 'target': 'area:Plaça Major', 'radius': 40, 'text': 'Ves a la Plaça Major'}]}
    m.update(kw)
    return m


class Validation(unittest.TestCase):
    def test_current_content_is_valid(self):
        for cid, (errors, _) in C.validate_all(DATA, REF).items():
            self.assertEqual(errors, [], cid)

    def test_rejects_invented_content(self):
        ch = copy.deepcopy(C.find(DATA, 'seguretat')[1])
        ch['missions'].append(mission('nova', cat='zzz', steps=[
            {'type': 'goto', 'target': 'area:Disneyland', 'text': 'Ves'},
            {'type': 'buy', 'items': ['corona_drac'], 'at': ['bonpreu'], 'text': 'Compra'},
            {'type': 'deliver', 'item': 'unicorn', 'target': 'service:metge', 'text': 'Porta'},
            {'type': 'enter', 'scene': 'lluna', 'text': 'Entra'},
            {'type': 'event', 'event': 'boom', 'text': 'x'},
            {'type': 'volar', 'text': 'x'},
            {'type': 'defeat', 'target': 'boss:kraken', 'text': 'x'}]))
        errors, _ = C.validate(ch, REF, DATA['chapters'])
        text = '\n'.join(errors)
        for frag in ('cat ha de ser', 'Disneyland', 'no es ven a bonpreu', 'unicorn', 'lluna', 'boom', 'volar', 'kraken'):
            self.assertIn(frag, text)

    def test_duplicate_ids_and_after_cycle(self):
        ch = copy.deepcopy(C.find(DATA, 'seguretat')[1])
        ch['missions'].append(mission('casa'))              # ya existe en «poble»
        ch['after'] = 'seguretat'
        errors, _ = C.validate(ch, REF, DATA['chapters'])
        self.assertTrue(any('ja existeix a la campanya «poble»' in e for e in errors))
        self.assertTrue(any('mateixa campanya' in e for e in errors))

    def test_placeholders_only_in_templates(self):
        ch = copy.deepcopy(C.find(DATA, 'familia')[1])
        self.assertEqual(C.validate(ch, REF, DATA['chapters'])[0], [])
        ch['templates']['visit']['steps'][0]['target'] = 'friend:{id}'
        self.assertEqual(C.validate(ch, REF, DATA['chapters'])[0], [])

    def test_flow_warning_for_undelivered_item(self):
        ch = {'id': 'proves', 'title': 'Proves', 'after': 'poble', 'unlock': 1, 'missions': [mission('p1', steps=[
            {'type': 'deliver', 'item': 'peluix', 'target': 'service:policia', 'text': 'Porta el peluix'}])]}
        errors, warnings = C.validate(ch, REF, DATA['chapters'])
        self.assertEqual(errors, [])
        self.assertTrue(any('peluix' in w for w in warnings))


class ImportExport(unittest.TestCase):
    def test_export_roundtrip(self):
        doc = C.export_doc(DATA, 'seguretat')
        self.assertEqual(doc['format'], C.FORMAT)
        self.assertIn('cau_drac', json.dumps(doc['reference'], ensure_ascii=False))
        self.assertIn('how_to', doc)
        ch, _ = C.parse_import(json.loads(json.dumps(doc)))
        self.assertEqual(ch, C.find(DATA, 'seguretat')[1])

    def test_bare_chapter_and_bad_format(self):
        ch, _ = C.parse_import(copy.deepcopy(C.find(DATA, 'poble')[1]))
        self.assertEqual(ch['id'], 'poble')
        with self.assertRaises(ValueError):
            C.parse_import({'format': 'altre', 'campaign': {}})
        with self.assertRaises(ValueError):
            C.parse_import({'format': C.FORMAT, 'version': 99, 'campaign': {}})

    def test_patch(self):
        base = C.find(DATA, 'seguretat')[1]
        p = {'format': C.PATCH_FORMAT, 'notes': 'n', 'upsert': [mission('nova', _after='passos'),
                                                              dict(base['missions'][1], title='Canviat')],
             'remove': ['autobus'], 'set': {'title': 'Nou títol', 'id': 'no_es_canvia'}}
        ch, notes = C.parse_import(p, base)
        ids = [m['id'] for m in ch['missions']]
        self.assertEqual(ids[:3], ['passos', 'nova', 'semafor'])
        self.assertNotIn('autobus', ids)
        self.assertEqual(ch['title'], 'Nou títol')
        self.assertEqual(ch['id'], 'seguretat')
        self.assertNotIn('_after', ch['missions'][1])
        d = C.diff(base, ch)
        self.assertEqual(d['added'], ['nova'])
        self.assertEqual(d['removed'], ['autobus'])
        self.assertEqual(d['changed'], {'semafor': ['title']})
        self.assertEqual(d['chapter'], ['title'])
        with self.assertRaises(ValueError):
            C.parse_import(p)                                # parche sin campaña base

    def test_template_in_upsert_goes_to_templates(self):
        base = C.find(DATA, 'familia')[1]
        tpl = mission('postal_tiets', roles=['tiet', 'tieta'], title='Una postal per a {name}',
                      steps=[{'type': 'talk', 'target': 'friend:{id}', 'text': 'Parla amb {name}'}])
        ch = C.apply_patch(base, {'upsert': [tpl]})
        self.assertIn('postal_tiets', ch['templates'])
        self.assertNotIn('id', ch['templates']['postal_tiets'])
        self.assertEqual(len(ch['missions']), len(base['missions']))
        self.assertEqual(C.validate(ch, REF, DATA['chapters'])[0], [])
        bad = dict(base, missions=base['missions'] + [dict(mission('x1'), title='Hola {name}')])
        self.assertTrue(any('marcadors' in e for e in C.validate(bad, REF, DATA['chapters'])[0]))

    def test_llm_prompt_is_compact(self):
        msgs = C.llm_messages(DATA, C.find(DATA, 'familia')[1], 'Afegeix una missió', C.reference(full=False))
        size = sum(len(m['content']) for m in msgs)
        self.assertLess(size, 24000)                         # ≈ 8k tokens: cabe en Groq gratis con la respuesta
        self.assertEqual(C.parse_llm('```json\n{"a":1}\n```'), {'a': 1})


class FileOps(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.tmp.name) / 'missions.json'
        shutil.copy(C.MISSIONS, self.path)
        self.p = [patch.object(C, 'MISSIONS', str(self.path)), patch.object(C, 'HISTORY', self.tmp.name + '/h')]
        for x in self.p: x.start()

    def tearDown(self):
        for x in self.p: x.stop()
        self.tmp.cleanup()

    def test_save_new_rename_delete_reorder(self):
        data = C.load()
        new = {'id': 'proves', 'title': 'Proves', 'after': 'seguretat', 'unlock': 1, 'missions': [mission('p1')]}
        data, errors, _ = C.save_chapter(data, 'proves', new)
        self.assertEqual(errors, [])
        C.write(data)
        self.assertEqual(self.path.read_text(encoding='utf-8'), C.dump(C.load()))
        self.assertTrue(list(pathlib.Path(self.tmp.name, 'h').iterdir()))
        data, errors, _ = C.save_chapter(data, 'seguretat', dict(C.find(data, 'seguretat')[1], id='seguretat2'))
        self.assertEqual(errors, [])
        self.assertEqual(C.find(data, 'proves')[1]['after'], 'seguretat2')        # dependientes siguen al renombrado
        with self.assertRaises(ValueError):
            C.delete_chapter(data, 'seguretat2')                                  # «proves» depende de ella
        data = C.delete_chapter(data, 'proves')
        self.assertIsNone(C.find(data, 'proves')[1])
        ids = [c['id'] for c in data['chapters']]
        data = C.reorder(data, ids[:1] + ids[1:][::-1])
        self.assertEqual([c['id'] for c in data['chapters']][1:], ids[1:][::-1])
        with self.assertRaises(ValueError):
            C.reorder(data, ids[:-1])

    def test_invalid_save_is_rejected(self):
        data = C.load()
        _, errors, _ = C.save_chapter(data, 'seguretat', dict(C.find(data, 'seguretat')[1], unlock=-1))
        self.assertTrue(errors)


class HTTP(unittest.TestCase):
    def test_campaign_api(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'missions.json'
            shutil.copy(C.MISSIONS, path)
            calls = []

            class FakeGroq:
                def __init__(self, req, timeout=None):
                    calls.append(json.loads(req.data))
                    reply = {'notes': 'Una missió nova', 'upsert': [mission('drac_extra', _after='passos')]}
                    self.raw = json.dumps({'text': json.dumps(reply), 'backend': 'groq', 'raw': {'usage': {'total_tokens': 1234}}}).encode()
                def __enter__(self): return self
                def __exit__(self, *a): return False
                def read(self, n=-1): return self.raw

            real_urlopen = server.urllib.request.urlopen
            with patch.object(C, 'MISSIONS', str(path)), patch.object(C, 'HISTORY', directory + '/h'), \
                 patch.object(server, 'verify_adult', return_value=True):
                srv = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
                th = threading.Thread(target=srv.serve_forever, daemon=True); th.start()
                try:
                    def req(method, url, body=None, headers=None):
                        conn = http.client.HTTPConnection(*srv.server_address, timeout=10)
                        conn.request(method, url, json.dumps(body) if body is not None else None,
                                     {'Content-Type': 'application/json', 'X-Roda-Request': '1', **(headers or {})})
                        r = conn.getresponse(); out = (r.status, dict(r.getheaders()), json.loads(r.read() or b'null')); conn.close()
                        return out
                    self.assertEqual(req('GET', '/api/campaigns')[0], 401)
                    st, hd, _ = req('POST', '/api/adult-check', {'pin': '1234'})
                    auth = {'Cookie': hd['Set-Cookie'].split(';')[0]}
                    st, hd, body = req('GET', '/api/campaigns', headers=auth)
                    self.assertEqual(st, 200)
                    self.assertEqual([c['id'] for c in body['campaigns']][:2], ['poble', 'familia'])
                    self.assertTrue(all(c['errors'] == 0 for c in body['campaigns']))
                    etag = hd['ETag']
                    st, _, doc = req('GET', '/api/campaigns/seguretat/export', headers=auth)
                    self.assertEqual((st, doc['format']), (200, C.FORMAT))
                    # importar el export con una misión nueva → diff
                    doc['campaign']['missions'].append(mission('drac_nova'))
                    st, _, imp = req('POST', '/api/campaigns/import', {'doc': doc}, auth)
                    self.assertEqual(st, 200)
                    self.assertEqual((imp['errors'], imp['diff']['added'], imp['exists']), ([], ['drac_nova'], True))
                    # guardar: sin If-Match 428, con uno viejo 409, con el bueno 200
                    self.assertEqual(req('PUT', '/api/campaigns/seguretat', imp['campaign'], auth)[0], 428)
                    self.assertEqual(req('PUT', '/api/campaigns/seguretat', imp['campaign'], {**auth, 'If-Match': '"x"'})[0], 409)
                    st, hd, out = req('PUT', '/api/campaigns/seguretat', imp['campaign'], {**auth, 'If-Match': etag})
                    self.assertEqual(st, 200, out)
                    self.assertIn('drac_nova', path.read_text(encoding='utf-8'))
                    etag = hd['ETag']
                    # guardar con errores → 400 y el fichero no cambia
                    bad = dict(imp['campaign'], missions=[mission('x', cat='zzz')])
                    before = path.read_text(encoding='utf-8')
                    st, _, out = req('PUT', '/api/campaigns/seguretat', bad, {**auth, 'If-Match': etag})
                    self.assertEqual(st, 400); self.assertIn('errors', out['error'])
                    self.assertEqual(path.read_text(encoding='utf-8'), before)
                    # IA simulada: parche aplicado y validado, no guarda
                    with patch.object(server.urllib.request, 'urlopen', side_effect=lambda r, timeout=None: FakeGroq(r, timeout)
                                      if r.full_url == server.HUB_GROQ else real_urlopen(r, timeout=timeout)):
                        st, _, ai = req('POST', '/api/campaigns/llm', {'campaign': imp['campaign'], 'instruction': 'Afegeix una missió'}, auth)
                    self.assertEqual(st, 200, ai)
                    self.assertEqual((ai['diff']['added'], ai['errors'], ai['tokens']), (['drac_extra'], [], 1234))
                    self.assertEqual([m['id'] for m in ai['campaign']['missions']][1], 'drac_extra')
                    self.assertEqual(calls[0]['response_format'], {'type': 'json_object'})
                    self.assertTrue(calls[0]['no_local'])
                    self.assertGreater(len(calls[0]['models']), 1)              # rotación de modelos del hub
                    self.assertEqual(path.read_text(encoding='utf-8'), before)
                    # borrar la primera no se puede; reordenar exige If-Match
                    st, hd, _ = req('GET', '/api/campaigns/poble', headers=auth)
                    self.assertEqual(req('DELETE', '/api/campaigns/poble', None, {**auth, 'If-Match': hd['ETag']})[0], 400)
                    self.assertEqual(req('POST', '/api/campaigns/order', {'ids': ['poble']}, auth)[0], 428)
                finally:
                    srv.shutdown(); srv.server_close(); th.join()


if __name__ == '__main__':
    unittest.main()
