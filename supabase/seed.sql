-- =====================================================================
-- Datos iniciales (ficticios) tomados de src/data/menu.json
-- Ejecutar DESPUÉS de schema.sql. No duplica datos si se ejecuta de nuevo.
-- =====================================================================

insert into public.categories (id, name, sort_order) values
  ('coffee', 'Cafetería', 0),
  ('cold', 'Bebidas frías', 1),
  ('bakery', 'Pastelería', 2),
  ('breakfast', 'Desayunos', 3),
  ('salty', 'Salados', 4)
on conflict (id) do nothing;

insert into public.products (category_id, name, description, price, image, available, featured, sort_order)
select * from (values
  ('coffee', 'Cappuccino', 'Espresso con leche vaporizada y espuma cremosa.', 3500::numeric, 'https://images.unsplash.com/photo-1570968915860-54d5c301fa9f?w=700', true, true, 0),
  ('coffee', 'Latte', 'Café espresso combinado con leche cremosa.', 3800::numeric, 'https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=700', true, true, 1),
  ('cold', 'Frappuccino', 'Bebida fría de café con hielo y crema.', 4500::numeric, 'https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=700', true, false, 2),
  ('bakery', 'Medialunas', 'Dos medialunas de manteca recién horneadas.', 2800::numeric, 'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=700', true, true, 3),
  ('bakery', 'Cheesecake', 'Porción de cheesecake con frutos rojos.', 5200::numeric, 'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?w=700', true, false, 4),
  ('salty', 'Tostado clásico', 'Jamón y queso en pan tostado.', 4800::numeric, 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=700', true, false, 5)
) as v (category_id, name, description, price, image, available, featured, sort_order)
where not exists (select 1 from public.products);
