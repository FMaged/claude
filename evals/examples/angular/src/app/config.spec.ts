import { parseConfig } from './config';

describe('parseConfig', () => {
  it('drops a trailing slash from the API URL', () => {
    expect(parseConfig({ apiUrl: 'https://api.test/', environment: 'staging' })).toEqual({
      apiUrl: 'https://api.test',
      environment: 'staging',
    });
  });

  it('names the missing key', () => {
    expect(() => parseConfig({ environment: 'staging' })).toThrow('config.json has no apiUrl');
    expect(() => parseConfig(null)).toThrow('config.json has no apiUrl');
  });
});
