import { createRouter, createWebHistory } from 'vue-router'
import { currentRole, currentStaff } from '../lib/auth'
import { ensurePanel, panel } from '../lib/panel'
import { allowedRoutes, canOpen } from '../lib/plans'

declare module 'vue-router' {
  interface RouteMeta {
    staff?: boolean
  }
}

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'menu',
      component: () => import('../views/public/MenuView.vue')
    },
    {
      path: '/mesa/:table',
      name: 'order-menu',
      component: () => import('../views/order/OrderMenuView.vue')
    },
    {
      path: '/pedir',
      name: 'remote-order',
      component: () => import('../views/order/OrderMenuView.vue')
    },
    {
      path: '/seguimiento/:code?',
      name: 'track',
      component: () => import('../views/order/TrackView.vue')
    },
    {
      path: '/pedido/:id',
      name: 'order-status',
      component: () => import('../views/order/OrderStatusView.vue')
    },
    {
      path: '/staff/login',
      name: 'staff-login',
      component: () => import('../views/staff/StaffLoginView.vue')
    },
    {
      path: '/staff',
      component: () => import('../views/staff/StaffLayout.vue'),
      meta: { staff: true },
      children: [
        {
          path: '',
          name: 'staff-orders',
          component: () => import('../views/staff/OrdersView.vue')
        },
        {
          path: 'productos',
          name: 'staff-products',
          component: () => import('../views/staff/ProductsView.vue')
        },
        {
          path: 'reparto',
          name: 'staff-run',
          component: () => import('../views/staff/RunView.vue')
        },
        {
          path: 'ajustes',
          name: 'staff-settings',
          component: () => import('../views/staff/SettingsView.vue')
        },
        {
          path: 'qr',
          name: 'staff-qr',
          component: () => import('../views/staff/QrView.vue')
        }
      ]
    },
    { path: '/:pathMatch(.*)*', redirect: '/' }
  ],
  scrollBehavior: () => ({ top: 0 })
})

// El panel requiere sesión de personal. La seguridad real está en la base (RLS);
// esto solo evita mostrar pantallas vacías a quien no corresponde.
router.beforeEach(async (to) => {
  if (!to.matched.some((record) => record.meta.staff)) return true

  if (!(await currentStaff())) return { name: 'staff-login', query: { redirect: to.fullPath } }

  // Cada persona entra solo a lo que permite su rol y el plan del local; si pide otra pantalla, va a la primera que le toca.
  const role = await currentRole()
  const name = String(to.name ?? '')

  if (name === 'staff-login') panel.ready = false // al iniciar sesión se vuelve a leer el rol y el plan

  if (name.startsWith('staff-') && name !== 'staff-login') {
    await ensurePanel()

    if (!canOpen(role, panel.plan, name)) {
      const home = allowedRoutes(role, panel.plan)[0]
      return home ? { name: home } : { name: 'staff-login' }
    }
  }

  return true
})

export default router
