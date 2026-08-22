// Ownership proof for customers who never create an account.
//
// The product promise is "leave a name and a number, done" — no login. That
// still leaves the question every booking system has to answer: when someone
// asks to cancel appointment X, how do we know it is theirs?
//
// Answer: at booking time the server mints a high-entropy manage token,
// returns it once, and stores only its SHA-256. The app keeps the token on the
// device. Presenting it proves ownership. Losing the device means phoning the
// shop, which is the same as it ever was.

import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

/** 256 bits, url-safe. Long enough that guessing is not a strategy. */
export function mintToken() {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token) {
  return createHash('sha256').update(String(token)).digest('hex');
}

/** Constant-time compare of two hex digests, safe on length mismatch. */
export function hashesEqual(a, b) {
  const ba = Buffer.from(String(a ?? ''), 'utf8');
  const bb = Buffer.from(String(b ?? ''), 'utf8');
  if (ba.length !== bb.length || ba.length === 0) return false;
  return timingSafeEqual(ba, bb);
}

/** A 6-digit numeric OTP, uniformly distributed (no modulo bias). */
export function mintOtp() {
  let n;
  do {
    n = randomBytes(4).readUInt32BE(0);
  } while (n >= 4294000000); // largest multiple of 1e6 below 2^32
  return String(n % 1000000).padStart(6, '0');
}

/**
 * Normalise a phone number to a comparable form: strip formatting, turn a
 * German national "0…" into "+49…". Without this "0176 123", "+49176123" and
 * "0049176123" are three different customers, and the loyalty card breaks.
 */
export function normalisePhone(raw, defaultCountry = '+49') {
  let s = String(raw ?? '').replace(/[\s\-().]/g, '');
  if (!s) return '';
  if (s.startsWith('00')) s = `+${s.slice(2)}`;
  if (s.startsWith('+')) return `+${s.slice(1).replace(/\D/g, '')}`;
  const digits = s.replace(/\D/g, '');
  if (digits.startsWith('0')) return `${defaultCountry}${digits.slice(1)}`;
  return `${defaultCountry}${digits}`;
}

export function looksLikePhone(normalised) {
  return /^\+\d{7,15}$/.test(String(normalised ?? ''));
}
