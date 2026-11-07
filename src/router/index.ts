import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'menu',
      component: () => import('../views/public/MenuView.vue')
    }
  ]
})

export default router