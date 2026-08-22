import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  mintToken, hashToken, hashesEqual, mintOtp, normalisePhone, looksLikePhone,
} from '../src/tokens.js';

test('manage tokens are long, unique and url-safe', () => {
  const seen = new Set();
  for (let i = 0; i < 200; i++) {
    const t = mintToken();
    assert.match(t, /^[A-Za-z0-9_-]{43}$/); // 32 bytes, base64url, unpadded
    assert.ok(!seen.has(t), 'token collision');
    seen.add(t);
  }
});

test('only the hash is comparable, and comparison is exact', () => {
  const token = mintToken();
  const stored = hashToken(token);
  assert.match(stored, /^[0-9a-f]{64}$/);
  assert.ok(hashesEqual(stored, hashToken(token)));
  assert.ok(!hashesEqual(stored, hashToken(mintToken())));
});

test('an absent or truncated hash never authorises', () => {
  const stored = hashToken(mintToken());
  assert.equal(hashesEqual(stored, ''), false);
  assert.equal(hashesEqual('', ''), false);
  assert.equal(hashesEqual(null, null), false);
  assert.equal(hashesEqual(undefined, hashToken('x')), false);
  assert.equal(hashesEqual(stored, stored.slice(0, 32)), false);
});

test('OTP codes are six digits and reasonably spread', () => {
  const seen = new Set();
  for (let i = 0; i < 500; i++) {
    const code = mintOtp();
    assert.match(code, /^\d{6}$/);
    seen.add(code);
  }
  // 500 draws from a million values should almost never repeat.
  assert.ok(seen.size > 495, `too many duplicate codes: ${seen.size}/500`);
});

test('German numbers normalise to one canonical form', () => {
  const expected = '+49176123456';
  for (const input of [
    '0176 123456',
    '0176123456',
    '+49 176 123456',
    '+49176123456',
    '0049176123456',
    '(0176) 123-456',
    ' 0176-123456 ',
  ]) {
    assert.equal(normalisePhone(input), expected, `failed for "${input}"`);
  }
});

test('normalisation is what makes the loyalty card hold together', () => {
  // Same customer, three ways of typing their number — one card, not three.
  const a = normalisePhone('0176 123456');
  const b = normalisePhone('+49176123456');
  const c = normalisePhone('0049 176 123456');
  assert.equal(a, b);
  assert.equal(b, c);
});

test('foreign numbers keep their own country code', () => {
  assert.equal(normalisePhone('+41 79 123 4567'), '+41791234567');
  assert.equal(normalisePhone('0041791234567'), '+41791234567');
});

test('nonsense is rejected rather than silently mangled', () => {
  assert.equal(normalisePhone(''), '');
  assert.equal(normalisePhone(null), '');
  assert.equal(looksLikePhone(normalisePhone('')), false);
  assert.equal(looksLikePhone(normalisePhone('123')), false);       // too short
  assert.equal(looksLikePhone(normalisePhone('abc')), false);
  assert.equal(looksLikePhone(normalisePhone('0176123456')), true);
});
