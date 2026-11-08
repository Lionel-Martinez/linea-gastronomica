import { createRouter, createWebHistory } from 'vue-router'
import { currentStaff, isManager } from '../lib/auth'

declare module 'vue-router' {
  interface RouteMeta {
    staff?: boolean
    manager?: boolean
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
          path: 'ajustes',
          name: 'staff-settings',
          meta: { manager: true },
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

  // Los ajustes del local son solo para encargados.
  if (to.matched.some((record) => record.meta.manager) && !(await isManager())) {
    return { name: 'staff-orders' }
  }

  return true
})

export default router
