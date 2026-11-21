#!/usr/bin/env python3
"""Genera un proyecto independiente (carpeta + .zip) por edición.
Uso: python3 scripts/exportar_ediciones.py <carpeta_de_salida>
Cada proyecto se publica con el comando por defecto: `npm run build`."""
import json, os, shutil, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]).resolve()
EDS = {
    'carta':    'Carta',
    'panel':    'Carta + Panel',
    'mesa':     'Carta + Panel + Mesa',
    'delivery': 'Pedidos y delivery',
    'completo': 'Completo',
}
SKIP = {'node_modules', 'dist', '.git', '.env', 'docs', 'scripts', '.wrangler'}

def copy_base(dst: Path):
    for item in ROOT.iterdir():
        if item.name in SKIP or item.name.startswith('dist-'):
            continue
        t = dst / item.name
        shutil.copytree(item, t) if item.is_dir() else shutil.copy2(item, t)

OUT.mkdir(parents=True, exist_ok=True)
for ed, label in EDS.items():
    name = f'linea-gastronomica-{ed}'
    d = OUT / name
    if d.exists():
        shutil.rmtree(d)
    d.mkdir()
    copy_base(d)

    # package.json: el comando por defecto compila SOLO esta edición
    p = json.loads((d / 'package.json').read_text())
    p['name'] = name
    p['scripts'] = {
        'dev': f'vite --mode {ed}',
        'build': f'vue-tsc -b && vite build --mode {ed}',
        'preview': 'vite preview',
    }
    (d / 'package.json').write_text(json.dumps(p, indent=2, ensure_ascii=False) + '\n')

    # wrangler: nombre propio
    w = (d / 'wrangler.jsonc').read_text().replace('"name": "linea-gastronomica"', f'"name": "{name}"')
    (d / 'wrangler.jsonc').write_text(w)

    # Supabase: solo lo que usa esta edición
    sb = d / 'supabase'
    if ed == 'carta':
        shutil.rmtree(sb)
    else:
        for f in (sb / 'editions').iterdir():
            if f.name != f'{ed}.sql':
                f.unlink()
        (sb / 'editions' / 'README.md').unlink(missing_ok=True)

    # Guía de la edición como README del proyecto
    g = (ROOT / 'docs' / 'ediciones' / f'{ed}.md').read_text()
    g = g.replace(f'npm run build:{ed}', 'npm run build')
    (d / 'README.md').write_text(g)

    z = OUT / f'{name}.zip'
    z.unlink(missing_ok=True)
    with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(d.rglob('*')):
            if f.is_file():
                zf.write(f, Path(name) / f.relative_to(d))
    print(f'{label:24} -> {z.name} ({z.stat().st_size // 1024} KB)')
