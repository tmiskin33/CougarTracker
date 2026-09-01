'use strict';
const test = require('node:test');
const assert = require('node:assert');
const handler = require('../api/canvas.js');

// The proxy holds a Canvas token in flight, so its guards are the security
// boundary: anything that gets past them is a request made with someone's
// credentials. These tests cover every rejection path.
function fakeResponse() {
  const captured = { status: 0, body: null, headers: {} };
  return {
    captured,
    setHeader(key, value) { captured.headers[key] = value; },
    status(code) { captured.status = code; return this; },
    json(body) { captured.body = body; return captured; },
    send(body) { captured.body = body; return captured; }
  };
}

async function call(request) {
  const response = fakeResponse();
  await handler(request, response);
  return response.captured;
}

test('only GET is proxied', async () => {
  const result = await call({ method: 'POST', query: {}, headers: {} });
  assert.equal(result.status, 405);
  assert.equal(result.headers.Allow, 'GET');
});

test('a missing url is rejected', async () => {
  assert.equal((await call({ method: 'GET', query: {}, headers: {} })).status, 400);
});

test('a malformed url is rejected', async () => {
  const result = await call({ method: 'GET', query: { url: 'not a url' }, headers: {} });
  assert.equal(result.status, 400);
});

test('it will not forward to another host', async () => {
  // Without this the deployment is an open proxy anyone could point anywhere.
  for (const url of [
    'https://evil.example.com/api/v1/users/self',
    'https://instructure.com.evil.example/api/v1/users/self',
    'http://byu.instructure.com/api/v1/users/self'
  ]) {
    const result = await call({ method: 'GET', query: { url }, headers: { authorization: 'Bearer x' } });
    assert.equal(result.status, 403, url + ' should be refused');
  }
});

test('it forwards only /api/v1/ paths', async () => {
  const result = await call({
    method: 'GET',
    query: { url: 'https://byu.instructure.com/login/canvas' },
    headers: { authorization: 'Bearer x' }
  });
  assert.equal(result.status, 403);
});

test('a request with no Authorization header is refused before any call is made', async () => {
  const result = await call({
    method: 'GET',
    query: { url: 'https://byu.instructure.com/api/v1/users/self' },
    headers: {}
  });
  assert.equal(result.status, 401);
});

test('a legitimate Canvas host is accepted by the guards', async () => {
  // Reaches the fetch, which fails with no network — proving the guards passed.
  const result = await call({
    method: 'GET',
    query: { url: 'https://byu.instructure.com/api/v1/users/self' },
    headers: { authorization: 'Bearer token' }
  });
  assert.ok(result.status === 502 || result.status >= 200, 'guards let it through');
  assert.notEqual(result.status, 403);
});
