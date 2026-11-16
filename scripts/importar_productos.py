#!/usr/bin/env python3
"""Convierte la planilla de productos de un local (CSV) en datos para el sistema.

  python3 scripts/importar_productos.py productos.csv --sql salida.sql       # ediciones con Supabase
  python3 scripts/importar_productos.py productos.csv --menu src/data/menu.json   # edición Carta

Columnas: categoria, producto, descripcion, precio, imagen, disponible, destacado
(disponible y destacado: si/no; vacío = si para disponible, no para destacado).
El SQL no duplica productos que ya existen (misma categoría y mismo nombre).
Si hay errores no se genera nada y se informan con el número de fila."""
import argparse, csv, io, json, re, sys, unicodedata
from pathlib import Path

COLS = ['categoria', 'producto', 'descripcion', 'precio', 'imagen', 'disponible', 'destacado']

def norm(t):
    t = unicodedata.normalize('NFD', t.strip().lower())
    return ''.join(c for c in t if unicodedata.category(c) != 'Mn')

def slug(t):
    s = re.sub(r'[^a-z0-9]+', '-', norm(t)).strip('-')
    return s or 'categoria'

def price(raw):
    s = re.sub(r'[^\d.,]', '', raw or '')
    if not s:
        raise ValueError('precio vacío')
    if ',' in s and '.' in s:
        s = s.replace('.', '').replace(',', '.') if s.rfind(',') > s.rfind('.') else s.replace(',', '')
    elif ',' in s:
        s = s.replace(',', '.') if len(s.split(',')[-1]) in (1, 2) else s.replace(',', '')
    elif '.' in s and len(s.split('.')[-1]) == 3:
        s = s.replace('.', '')
    v = float(s)
    if v <= 0:
        raise ValueError('el precio debe ser mayor a 0')
    return int(v) if v == int(v) else round(v, 2)

def yes(raw, default):
    v = norm(raw or '')
    if v == '':
        return default
    if v in ('si', 's', 'yes', 'y', 'true', '1', 'x'):
        return True
    if v in ('no', 'n', 'false', '0'):
        return False
    raise ValueError(f'«{raw}» no es si/no')

def read(path):
    text = Path(path).read_text(encoding='utf-8-sig')
    delim = ';' if text.splitlines()[0].count(';') > text.splitlines()[0].count(',') else ','
    rd = csv.DictReader(io.StringIO(text), delimiter=delim)
    rd.fieldnames = [norm(f) for f in (rd.fieldnames or [])]
    missing = [c for c in COLS if c not in rd.fieldnames]
    if missing:
        sys.exit(f'Faltan columnas: {", ".join(missing)}. Usá plantillas/productos-modelo.csv')
    cats, prods, errors, seen = {}, [], [], set()
    for n, row in enumerate(rd, start=2):
        if not any((v or '').strip() for v in row.values()):
            continue
        try:
            cat, name = (row['categoria'] or '').strip(), (row['producto'] or '').strip()
            if not cat: raise ValueError('falta la categoría')
            if not name: raise ValueError('falta el nombre del producto')
            img = (row['imagen'] or '').strip()
            if img and not re.match(r'^https://', img): raise ValueError('la imagen debe ser un enlace que empiece con https://')
            key = (slug(cat), norm(name))
            if key in seen: raise ValueError(f'producto repetido en la categoría «{cat}»')
            seen.add(key)
            cats.setdefault(slug(cat), cat)
            prods.append(dict(cat=slug(cat), name=name, description=(row['descripcion'] or '').strip(),
                              price=price(row['precio']), image=img,
                              available=yes(row['disponible'], True), featured=yes(row['destacado'], False)))
        except ValueError as e:
            errors.append(f'  fila {n}: {e}')
    if errors:
        sys.exit('No se generó nada. Corregí estas filas:\n' + '\n'.join(errors))
    if not prods:
        sys.exit('La planilla no tiene productos.')
    return cats, prods

def q(t): return "'" + t.replace("'", "''") + "'"

def to_sql(cats, prods):
    out = ['-- Productos del local (generado por scripts/importar_productos.py)',
           '-- Ejecutar en el SQL Editor del Supabase del local. No duplica lo que ya existe.', '',
           'insert into public.categories (id, name, sort_order) values']
    out.append(',\n'.join(f'  ({q(i)}, {q(n)}, {k})' for k, (i, n) in enumerate(cats.items())))
    out.append('on conflict (id) do update set name = excluded.name;\n')
    out.append('insert into public.products (category_id, name, description, price, image, available, featured, sort_order)')
    out.append('select * from (values')
    rows = [f"  ({q(p['cat'])}, {q(p['name'])}, {q(p['description'])}, {p['price']}::numeric, {q(p['image'])}, "
            f"{str(p['available']).lower()}, {str(p['featured']).lower()}, {k})" for k, p in enumerate(prods)]
    out.append(',\n'.join(rows))
    out.append(') as v (category_id, name, description, price, image, available, featured, sort_order)')
    out.append('where not exists (select 1 from public.products x where x.category_id = v.category_id and lower(x.name) = lower(v.name));')
    out.append(f'\nselect count(*) as productos from public.products;')
    return '\n'.join(out) + '\n'

def to_menu(path, cats, prods):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    data['categories'] = [{'id': 'all', 'name': 'Todos'}] + [{'id': i, 'name': n} for i, n in cats.items()]
    data['products'] = [dict(id=k + 1, name=p['name'], description=p['description'], price=p['price'],
                             category=p['cat'], image=p['image'], featured=p['featured'], available=p['available'])
                        for k, p in enumerate(prods)]
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('csv'); ap.add_argument('--sql'); ap.add_argument('--menu')
    a = ap.parse_args()
    if bool(a.sql) == bool(a.menu):
        sys.exit('Indicá una salida: --sql archivo.sql (Supabase) o --menu src/data/menu.json (edición Carta)')
    cats, prods = read(a.csv)
    if a.sql: Path(a.sql).write_text(to_sql(cats, prods), encoding='utf-8')
    else: to_menu(a.menu, cats, prods)
    print(f'Listo: {len(cats)} categorías y {len(prods)} productos.')
