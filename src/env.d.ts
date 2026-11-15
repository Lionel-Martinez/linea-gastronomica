/** Edición que se está compilando (la fija vite.config.ts según el modo: `vite build --mode panel`). */
declare const __EDITION__: 'carta' | 'panel' | 'mesa' | 'delivery' | 'completo'
declare const __HAS_BACKEND__: boolean
declare const __HAS_PUBLIC_MENU__: boolean
declare const __HAS_TABLE_ORDERING__: boolean
declare const __HAS_REMOTE_ORDERING__: boolean
declare const __HAS_QR_PAGE__: boolean
