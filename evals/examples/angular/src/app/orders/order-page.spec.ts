import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { APP_CONFIG } from '../config';
import { OrderPage } from './order-page';

describe('OrderPage', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: APP_CONFIG, useValue: { apiUrl: 'https://api.test', environment: 'test' } },
      ],
    });
  });

  afterEach(() => TestBed.inject(HttpTestingController).verify());

  it('shows the order from the API', async () => {
    const fixture = TestBed.createComponent(OrderPage);
    fixture.componentRef.setInput('id', '1');
    TestBed.tick();
    TestBed.inject(HttpTestingController)
      .expectOne('https://api.test/orders/1')
      .flush({ id: 1, name: 'First order' });
    await fixture.whenStable();
    expect((fixture.nativeElement as HTMLElement).querySelector('h1')?.textContent).toBe('First order');
  });

  it('says so when the API fails', async () => {
    const fixture = TestBed.createComponent(OrderPage);
    fixture.componentRef.setInput('id', '2');
    TestBed.tick();
    TestBed.inject(HttpTestingController)
      .expectOne('https://api.test/orders/2')
      .flush(null, { status: 404, statusText: 'Not Found' });
    await fixture.whenStable();
    expect((fixture.nativeElement as HTMLElement).querySelector('[role=alert]')?.textContent).toContain('Order 2');
  });
});
