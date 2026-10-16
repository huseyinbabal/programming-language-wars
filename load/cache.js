// Same load for every implementation, at the same time: a fixed number of requests per second each.
// Cache-aside traffic: GET the key, and PUT a value when the GET was a miss.
// 20% of requests go to 100 hot keys, the rest spread over KEYS keys (more than CAPACITY, so the cache evicts).
//   TARGETS=go=http://go:8000,rust=http://rust:8000 RATE=5000 k6 run load/cache.js
import http from 'k6/http';
import { check } from 'k6';

const TARGETS = (__ENV.TARGETS || 'go=http://127.0.0.1:8001,rust=http://127.0.0.1:8002')
  .split(',').map((t) => t.split('='));
const RATE = parseInt(__ENV.RATE || '5000');           // requests per second, per implementation (misses add a PUT)
const KEYS = parseInt(__ENV.KEYS || '1000000');
const HOT_KEYS = 100, HOT_SHARE = 0.2;
const DURATION = __ENV.DURATION || '1h';                // the container restarts k6 when it ends

const scenarios = {};
for (const [impl, url] of TARGETS) {
  scenarios[impl] = {
    executor: 'constant-arrival-rate', exec: 'run', rate: RATE, timeUnit: '1s', duration: DURATION,
    preAllocatedVUs: 200, maxVUs: 2000, tags: { impl }, env: { BASE: url },
  };
}

export const options = {
  scenarios,
  // no url tag: one series per endpoint instead of one per key
  systemTags: ['status', 'method', 'name', 'scenario', 'expected_response'],
  summaryTrendStats: ['p(50)', 'p(99)', 'max'],
};

// 16 values between 100 and 1000 bytes, built once
const VALUES = Array.from({ length: 16 }, (_, i) => 'v'.repeat(100 + i * 60));
const GET = { tags: { name: 'GET /kv/{key}' }, responseCallback: http.expectedStatuses(200, 404) };
const PUT = { tags: { name: 'PUT /kv/{key}' } };

export function run() {
  const key = Math.random() < HOT_SHARE ? `hot${Math.floor(Math.random() * HOT_KEYS)}` : `k${Math.floor(Math.random() * KEYS)}`;
  const res = http.get(`${__ENV.BASE}/kv/${key}`, GET);
  if (res.status === 404) {
    const put = http.put(`${__ENV.BASE}/kv/${key}`, VALUES[Math.floor(Math.random() * VALUES.length)], PUT);
    check(put, { 'put 204': (r) => r.status === 204 });
  } else {
    check(res, { 'get 200': (r) => r.status === 200 });
  }
}
