#!/usr/bin/env python3
"""Publica una rama por edición (edicion/carta, edicion/panel, edicion/mesa, edicion/delivery, edicion/completo).

Cada rama es una COPIA GENERADA de main para esa edición (mismo contenido que el zip): `npm run build` compila solo esa
edición y el wrangler lleva su propio nombre. En Cloudflare cada proyecto se conecta a su rama y tiene sus propias variables.
NUNCA se edita una rama de edición a mano: los cambios van a main y se vuelven a publicar con este script.

Uso (desde la carpeta del repo, con main actualizado y sin cambios sin guardar):
  python3 scripts/publicar_ramas.py            # genera y sube las 5 ramas
  python3 scripts/publicar_ramas.py panel mesa # solo algunas
"""
import shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALL = ['carta', 'panel', 'mesa', 'delivery', 'completo']
eds = sys.argv[1:] or ALL
for e in eds:
    if e not in ALL: sys.exit(f'Edición desconocida: {e}')

def git(*a, cwd=ROOT, check=True):
    return subprocess.run(['git', *a], cwd=cwd, check=check, capture_output=True, text=True).stdout.strip()

if git('status', '--porcelain'): sys.exit('Hay cambios sin guardar: hacer commit primero.')
if git('rev-parse', '--abbrev-ref', 'HEAD') != 'main': sys.exit('Ejecutar desde la rama main.')
git('pull', '--rebase', 'origin', 'main')
sha = git('rev-parse', '--short', 'HEAD')

tmp = Path(tempfile.mkdtemp(prefix='ramas-'))
subprocess.run([sys.executable, str(ROOT / 'scripts' / 'exportar_ediciones.py'), str(tmp / 'out')], check=True, capture_output=True)
for ed in eds:
    branch = f'edicion/{ed}'
    wt = tmp / f'wt-{ed}'
    git('fetch', 'origin', f'+refs/heads/{branch}:refs/remotes/origin/{branch}', check=False)
    base = f'origin/{branch}' if git('rev-parse', '--verify', '-q', f'origin/{branch}', check=False) else 'HEAD'
    git('worktree', 'add', '-B', branch, str(wt), base)
    for item in wt.iterdir():
        if item.name != '.git': shutil.rmtree(item) if item.is_dir() else item.unlink()
    src = tmp / 'out' / f'linea-gastronomica-{ed}'
    for item in src.iterdir():
        t = wt / item.name
        shutil.copytree(item, t) if item.is_dir() else shutil.copy2(item, t)
    git('add', '-A', cwd=wt)
    if git('status', '--porcelain', cwd=wt):
        git('commit', '-qm', f'Edición {ed} generada desde main@{sha}', cwd=wt)
    git('push', '-q', 'origin', branch, cwd=wt)
    git('worktree', 'remove', '--force', str(wt))
    print(f'{branch}: publicada (desde main@{sha})')
shutil.rmtree(tmp, ignore_errors=True)
