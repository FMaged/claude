import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';
import { APP_CONFIG, parseConfig } from './app/config';

// Each server provides its own config.json, so one build serves every environment.
fetch('config.json', { cache: 'no-store' })
  .then((response) => {
    if (!response.ok) {
      throw new Error(`config.json: HTTP ${response.status}`);
    }
    return response.json();
  })
  .then((json: unknown) =>
    bootstrapApplication(App, {
      ...appConfig,
      providers: [...appConfig.providers, { provide: APP_CONFIG, useValue: parseConfig(json) }],
    }),
  )
  .catch((err: unknown) => {
    console.error(err);
    document.body.textContent = 'The app could not start. Reload the page, or contact support.';
  });
