import { Component, inject } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';
import { APP_CONFIG } from './config';

@Component({
  selector: 'app-root',
  imports: [RouterLink, RouterOutlet],
  template: `
    <header>
      <a routerLink="/orders/1">Order 1</a>
      @if (environment !== 'production') {
        <span class="environment">{{ environment }}</span>
      }
    </header>
    <main>
      <router-outlet />
    </main>
  `,
  styles: `
    .environment {
      margin-left: 1rem;
      padding: 0 0.5rem;
      background: #fde68a;
    }
  `,
})
export class App {
  protected readonly environment = inject(APP_CONFIG).environment;
}
