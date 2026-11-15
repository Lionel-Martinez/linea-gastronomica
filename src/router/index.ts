import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import {
  HAS_BACKEND,
  HAS_ORDERS,
  HAS_PUBLIC_MENU,
  HAS_QR_PAGE,
  HAS_REMOTE_ORDERING,
  HAS_TABLE_ORDERING
} from '../edition'

declare module 'vue-router' {
  interface RouteMeta {
    staff?: boolean
  }
}

// Las rutas dependen de la edición: lo que no incluye no existe (la dirección redirige a la carta).
const routes: RouteRecordRaw[] = []

routes.push(
  HAS_PUBLIC_MENU
    ? { path: '/', name: 'menu', component: () => import('../views/public/MenuView.vue') }
    : { path: '/', redirect: { name: 'remote-order' } } // Pedidos y delivery: no hay carta pública
)

if (HAS_TABLE_ORDERING) {
  routes.push({ path: '/mesa/:table', name: 'order-menu', component: () => import('../views/order/OrderMenuView.vue') })
}

if (HAS_REMOTE_ORDERING) {
  routes.push(
    { path: '/pedir', name: 'remote-order', component: () => import('../views/order/OrderMenuView.vue') },
    { path: '/seguimiento/:code?', name: 'track', component: () => import('../views/order/TrackView.vue') }
  )
}

if (HAS_ORDERS) {
  routes.push({ path: '/pedido/:id', name: 'order-status', component: () => import('../views/order/OrderStatusView.vue') })
}

// Carta (sin servidor ni login): página de QR del sitio, sin enlace público desde la carta.
if (!HAS_BACKEND && HAS_QR_PAGE) {
  routes.push({ path: '/qr', name: 'public-qr', component: () => import('../views/staff/QrView.vue') })
}

if (HAS_BACKEND) {
  const children: RouteRecordRaw[] = []

  if (HAS_ORDERS) {
    children.push({ path: '', name: 'staff-orders', component: () => import('../views/staff/OrdersView.vue') })
  }

  children.push({ path: 'productos', name: 'staff-products', component: () => import('../views/staff/ProductsView.vue') })

  if (HAS_REMOTE_ORDERING) {
    children.push({ path: 'reparto', name: 'staff-run', component: () => import('../views/staff/RunView.vue') })
  }

  if (HAS_ORDERS) {
    children.push({ path: 'ajustes', name: 'staff-settings', component: () => import('../views/staff/SettingsView.vue') })
  }

  if (HAS_QR_PAGE) {
    children.push({ path: 'qr', name: 'staff-qr', component: () => import('../views/staff/QrView.vue') })
  }

  routes.push(
    { path: '/staff/login', name: 'staff-login', component: () => import('../views/staff/StaffLoginView.vue') },
    {
      path: '/staff',
      component: () => import('../views/staff/StaffLayout.vue'),
      meta: { staff: true },
      // En «Carta + Panel» el panel arranca en Productos; en las demás, en Pedidos.
      redirect: () => ({ name: children[0].name }),
      children
    }
  )
}

routes.push({ path: '/:pathMatch(.*)*', redirect: '/' })

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 })
})

// El panel requiere sesión de personal. La seguridad real está en la base (RLS);
// esto solo evita mostrar pantallas vacías a quien no corresponde.
if (HAS_BACKEND) {
  router.beforeEach(async (to) => {
    // Al ir a iniciar sesión se olvida el rol y el plan anteriores (puede entrar otra persona).
    if (to.name === 'staff-login') (await import('../lib/panel')).panel.ready = false

    if (!to.matched.some((record) => record.meta.staff)) return true

    const [{ currentRole, currentStaff }, { ensurePanel, panel }, { allowedRoutes, canOpen }] = await Promise.all([
      import('../lib/auth'),
      import('../lib/panel'),
      import('../lib/plans')
    ])

    if (!(await currentStaff())) return { name: 'staff-login', query: { redirect: to.fullPath } }

    // Cada persona entra solo a lo que permite su rol y el plan del local; si pide otra pantalla, va a la primera que le toca.
    const role = await currentRole()
    const name = String(to.name ?? '')

    if (name.startsWith('staff-') && name !== 'staff-login') {
      await ensurePanel()

      if (!canOpen(role, panel.plan, name)) {
        const home = allowedRoutes(role, panel.plan)[0]
        return home ? { name: home } : { name: 'staff-login' }
      }
    }

    return true
  })
}

export default router
