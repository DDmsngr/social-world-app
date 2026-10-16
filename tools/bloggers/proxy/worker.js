// Прокси к Anthropic для сервера в РФ: Anthropic не принимает запросы с российских IP.
// Пускает только POST /v1/messages с верным X-Proxy-Token; ключ Anthropic приходит
// от вызывающего (x-api-key) и тут не хранится, поэтому один токен без ключа бесполезен.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== 'POST' || url.pathname !== '/v1/messages') {
      return new Response('not found', { status: 404 });
    }
    const token = request.headers.get('x-proxy-token') || '';
    if (!env.PROXY_TOKEN || token !== env.PROXY_TOKEN) {
      return new Response('forbidden', { status: 403 });
    }
    const headers = new Headers();
    for (const name of ['content-type', 'x-api-key', 'anthropic-version', 'anthropic-beta']) {
      const value = request.headers.get(name);
      if (value) headers.set(name, value);
    }
    return fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers,
      body: request.body,
    });
  },
};
