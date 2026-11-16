# Editions

Un **solo proyecto de Supabase** atiende a todos los locales. Cada archivo da de alta un local con el plan de su edición
(o le cambia la edición si ya existe). Ver `docs/ediciones/README.md`.

1. Abrir el archivo de la edición, cambiar `v_slug` y `v_name`, pegarlo en el SQL Editor y ejecutarlo.
2. Crear el usuario del encargado en Authentication → Users y asignarlo al local:
   `select public.add_staff('encargado@correo.com', 'mi-local', 'manager');`
3. Compilar el sitio del local con `VITE_TENANT=mi-local`.

La edición **carta** no usa Supabase, por eso no tiene archivo.
