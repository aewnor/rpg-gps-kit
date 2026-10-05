#!/usr/bin/env python3
"""Campañas de misiones desde la terminal (misma lógica que el editor /editor/missions.html).

  python3 tools/campaign.py list
  python3 tools/campaign.py export drac [-o drac.json]      JSON con instrucciones + referencia para un LLM
  python3 tools/campaign.py check fichero.json [--base drac] valida (y aplica si es un parche) sin guardar
  python3 tools/campaign.py import fichero.json [--base drac] valida y guarda en data/missions.json
  python3 tools/campaign.py validate                         valida todas las campañas guardadas
"""
import argparse
import json
import sys

import campaigns as C


def show(errors, warnings):
    for e in errors:
        print('ERROR', e)
    for w in warnings:
        print('AVÍS ', w)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('cmd', choices=['list', 'export', 'check', 'import', 'validate'])
    ap.add_argument('arg', nargs='?')
    ap.add_argument('-o', '--out')
    ap.add_argument('--base', help='campaña sobre la que aplicar un parche')
    a = ap.parse_args()
    data = C.load()
    if a.cmd == 'list':
        for c in data['chapters']:
            print(f"{c['id']:<12} {len(c.get('missions') or []):>3} missions  {c.get('title')}"
                  + (f"  (després de {c['after']}, {c.get('unlock', 0)})" if c.get('after') else ''))
        return 0
    if a.cmd == 'validate':
        bad = 0
        for cid, (errors, warnings) in C.validate_all(data).items():
            print(f'== {cid}: {len(errors)} errors, {len(warnings)} avisos')
            show(errors, warnings)
            bad += len(errors)
        return 1 if bad else 0
    if a.cmd == 'export':
        doc = C.export_doc(data, a.arg)
        txt = json.dumps(doc, ensure_ascii=False, indent=2)
        if a.out:
            open(a.out, 'w', encoding='utf-8').write(txt)
            print('Desat a', a.out)
        else:
            print(txt)
        return 0
    with open(a.arg, encoding='utf-8') as f:
        doc = json.load(f)
    base = C.find(data, a.base)[1] if a.base else None
    ch, notes = C.parse_import(doc, base)
    old = base or C.find(data, ch.get('id'))[1]
    errors, warnings = C.validate(ch, C.reference(), [c for c in data['chapters'] if c.get('id') != (a.base or ch.get('id'))])
    if notes:
        print('Notes:', notes)
    print(json.dumps(C.diff(old, ch), ensure_ascii=False))
    show(errors, warnings)
    if a.cmd == 'check' or errors:
        return 1 if errors else 0
    new, errors, _ = C.save_chapter(data, a.base or ch['id'], ch)
    if errors:
        show(errors, [])
        return 1
    C.write(new)
    print('Guardat a data/missions.json (còpia a data/.history/). Publica des de l\'editor o amb tools/build_web.sh --activate.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
