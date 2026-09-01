// Server-side proxy for the Canvas API.
//
// Why this exists: Canvas sends no Access-Control-Allow-Origin header and 404s
// the CORS preflight, so a browser refuses to call it from a web page. A
// server-to-server request has no such restriction, so this function makes the
// call and hands the result back to the page that asked.
//
// It is deliberately narrow, because a forwarder that will fetch anything is an
// open proxy:
//   - GET only
//   - the target must be an *.instructure.com host over https
//   - the path must start with /api/v1/
//   - no Access-Control-Allow-Origin is set, so only pages served from this
//     same deployment can use it
//
// The caller's Canvas token passes through this function in memory to reach
// Canvas. It is never logged, stored, or written anywhere. That is still a
// weaker position than the iOS app, which never lets the token leave the
// device — see the security note in web/README.md.

const ALLOWED_HOST = /^[a-z0-9-]+(\.[a-z0-9-]+)*\.instructure\.com$/i;
const ALLOWED_PATH = /^\/api\/v1\//;

module.exports = async function handler(request, response) {
  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET');
    return response.status(405).json({ error: 'Only GET is proxied.' });
  }

  const raw = request.query && request.query.url;
  if (!raw || Array.isArray(raw)) {
    return response.status(400).json({ error: 'Pass the Canvas URL as ?url=' });
  }

  let target;
  try {
    target = new URL(raw);
  } catch (_) {
    return response.status(400).json({ error: 'That is not a valid URL.' });
  }

  if (target.protocol !== 'https:' || !ALLOWED_HOST.test(target.hostname)) {
    return response.status(403).json({
      error: 'This proxy only forwards to https://*.instructure.com.'
    });
  }
  if (!ALLOWED_PATH.test(target.pathname)) {
    return response.status(403).json({ error: 'This proxy only forwards /api/v1/ requests.' });
  }

  const authorization = request.headers.authorization;
  if (!authorization) {
    return response.status(401).json({ error: 'Missing Authorization header.' });
  }

  let upstream;
  try {
    upstream = await fetch(target.toString(), {
      method: 'GET',
      headers: { Authorization: authorization, Accept: 'application/json' }
    });
  } catch (_) {
    return response.status(502).json({ error: 'Could not reach Canvas.' });
  }

  // Pagination lives in the Link header, so it has to survive the hop.
  const link = upstream.headers.get('link');
  if (link) response.setHeader('Link', link);
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');

  const body = await upstream.text();
  return response.status(upstream.status).send(body);
};
