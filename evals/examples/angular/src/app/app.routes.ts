import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: 'orders/:id',
    loadComponent: () => import('./orders/order-page').then((m) => m.OrderPage),
  },
];
