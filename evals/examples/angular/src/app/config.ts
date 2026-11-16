import { InjectionToken } from '@angular/core';

export interface AppConfig {
  readonly apiUrl: string;
  readonly environment: string;
}

export const APP_CONFIG = new InjectionToken<AppConfig>('APP_CONFIG');

// config.json comes from the server, so check it before the app relies on it.
export function parseConfig(json: unknown): AppConfig {
  const config = (json ?? {}) as Partial<AppConfig>;
  if (typeof config.apiUrl !== 'string' || config.apiUrl === '') {
    throw new Error('config.json has no apiUrl');
  }
  if (typeof config.environment !== 'string' || config.environment === '') {
    throw new Error('config.json has no environment');
  }
  return { apiUrl: config.apiUrl.replace(/\/+$/, ''), environment: config.environment };
}
