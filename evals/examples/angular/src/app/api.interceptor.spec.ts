import { TestBed } from '@angular/core/testing';
import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { Router, provideRouter } from '@angular/router';
import { apiInterceptor } from './api.interceptor';
import { APP_CONFIG } from './config';

describe('apiInterceptor', () => {
  let http: HttpClient;
  let backend: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([apiInterceptor])),
        provideHttpClientTesting(),
        provideRouter([]),
        { provide: APP_CONFIG, useValue: { apiUrl: 'https://api.test', environment: 'test' } },
      ],
    });
    http = TestBed.inject(HttpClient);
    backend = TestBed.inject(HttpTestingController);
  });

  afterEach(() => backend.verify());

  it('sends credentials to the API only', () => {
    http.get('https://api.test/orders/1').subscribe();
    http.get('https://api.test.example.com/orders/1').subscribe();
    expect(backend.expectOne('https://api.test/orders/1').request.withCredentials).toBe(true);
    expect(backend.expectOne('https://api.test.example.com/orders/1').request.withCredentials).toBe(false);
  });

  it('sends the user to the login page on a 401 from the API', () => {
    const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);
    http.get('https://api.test/orders/1').subscribe({ error: () => undefined });
    backend.expectOne('https://api.test/orders/1').flush(null, { status: 401, statusText: 'Unauthorized' });
    expect(navigate).toHaveBeenCalledWith(['/login'], { queryParams: { returnUrl: '/' } });
  });
});
