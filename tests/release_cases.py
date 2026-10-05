import importlib.util,pathlib,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ReleaseTests(unittest.TestCase):
 def test_incomplete_candidate_keeps_active_and_rollback_works(self):
  spec=importlib.util.spec_from_file_location('release',ROOT/'tools/web_release.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);(root/'build').mkdir();(root/'releases').mkdir()
   old=root/'releases/old';old.mkdir()
   for n in m.REQUIRED:(old/n).write_bytes(b'old')
   (root/'build/web').symlink_to(old)
   bad=root/'bad';bad.mkdir()
   with self.assertRaises(ValueError):m.finalize(root,bad,'bad',activate=True)
   self.assertEqual((root/'build/web').resolve(),old)
   candidate=root/'candidate';candidate.mkdir()
   for n in m.REQUIRED:(candidate/n).write_bytes(b'new')
   (candidate/'index.html').write_text('<head></head><script src="game.js"></script><script src="love.js"></script>')
   new=m.finalize(root,candidate,'new',activate=True)
   self.assertEqual((root/'build/web').resolve(),new)
   self.assertIn('/releases/new/game.js',(new/'index.html').read_text())
   self.assertTrue((new/'manifest.json').exists())
   m.activate_release(root,old);self.assertEqual((root/'build/web').resolve(),old)
if __name__=='__main__':unittest.main()
