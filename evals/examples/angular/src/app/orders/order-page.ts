import { Component, inject, input } from '@angular/core';
import { httpResource } from '@angular/common/http';
import { APP_CONFIG } from '../config';

interface Order {
  readonly id: number;
  readonly name: string;
}

@Component({
  selector: 'app-order-page',
  template: `
    @if (order.error()) {
      <p role="alert">Order {{ id() }} could not be loaded.</p>
    } @else if (order.isLoading()) {
      <p>Loading…</p>
    } @else {
      <h1>{{ order.value()?.name }}</h1>
    }
  `,
})
export class OrderPage {
  // The route parameter :id, bound by withComponentInputBinding().
  readonly id = input.required<string>();

  private readonly apiUrl = inject(APP_CONFIG).apiUrl;

  protected readonly order = httpResource<Order>(
    () => `${this.apiUrl}/orders/${encodeURIComponent(this.id())}`,
  );
}
