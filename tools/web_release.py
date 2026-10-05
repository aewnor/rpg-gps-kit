"""Finalize a staged web build, then optionally switch the active symlink atomically."""
import argparse, hashlib, json, os, pathlib, re, secrets
REQUIRED=('index.html','game.js','game.data','love.js','love.wasm')

def validate(directory):
    directory=pathlib.Path(directory)
    if any(not (directory/n).is_file() or not (directory/n).stat().st_size for n in REQUIRED):
        raise ValueError('Incomplete web candidate')

def activate_release(root, release):
    root=pathlib.Path(root);release=pathlib.Path(release).resolve();validate(release)
    if release.parent != (root/'releases').resolve():raise ValueError('Release outside release directory')
    active=root/'build/web'
    if active.exists() and not active.is_symlink():raise ValueError('Active web must be a symlink; preserve the legacy directory first')
    tmp=root/'build'/('.web-'+secrets.token_hex(8))
    os.symlink(release,tmp)
    try:os.replace(tmp,active)
    finally:
        if tmp.is_symlink():tmp.unlink()

def finalize(root, candidate, release_id, activate=False):
    root=pathlib.Path(root).resolve();candidate=pathlib.Path(candidate).resolve()
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,79}',release_id):raise ValueError('Invalid release id')
    validate(candidate)
    dest=root/'releases'/release_id
    if dest.exists():raise ValueError('Release exists')
    base='/releases/'+release_id+'/'
    html=(candidate/'index.html').read_text()
    html=html.replace('</head>','<script>window.RODA_RELEASE_BASE='+json.dumps(base)+';</script>\n</head>')
    # Only our own static JavaScript is release-versioned; hub stays shared.
    for file in candidate.glob('*.js'):
        html=html.replace('src="'+file.name+'"','src="'+base+file.name+'"')
    (candidate/'index.html').write_text(html)
    manifest={str(p.relative_to(candidate)):hashlib.sha256(p.read_bytes()).hexdigest() for p in candidate.rglob('*') if p.is_file()}
    (candidate/'manifest.json').write_text(json.dumps(manifest,indent=2))
    dest.parent.mkdir(parents=True,exist_ok=True);os.rename(candidate,dest)
    if activate:activate_release(root,dest)
    return dest

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('candidate');p.add_argument('release_id');p.add_argument('--activate',action='store_true');a=p.parse_args()
    print(finalize(pathlib.Path(__file__).resolve().parents[1],a.candidate,a.release_id,a.activate))
