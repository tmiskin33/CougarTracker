// Input rules, kept in one place so the endpoints and the tests agree.
'use strict';

// Deliberately permissive: the only real proof an address works is that the
// verification email arrives, so this rejects obvious nonsense and nothing more.
const EMAIL = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;

const MIN_PASSWORD = 10;

// Length beats character classes. A handful of the passwords that show up
// first in every breach list, rejected by exact match rather than a rule that
// pushes people towards "Password1!".
const TOO_COMMON = new Set([
  'password', 'password1', 'password123', '1234567890', '12345678',
  'qwertyuiop', 'letmein123', 'iloveyou1', 'admin12345', 'welcome123',
  'passw0rd!', 'football123', 'baseball12', 'sunshine12', 'princess12'
]);

function normaliseEmail(email) {
  return String(email == null ? '' : email).trim().toLowerCase();
}

function checkEmail(email) {
  const value = normaliseEmail(email);
  if (!value) return 'Enter your email address.';
  if (value.length > 254) return 'That email address is too long.';
  if (!EMAIL.test(value)) return 'That does not look like an email address.';
  return null;
}

function checkPassword(password, email) {
  const value = String(password == null ? '' : password);
  if (value.length < MIN_PASSWORD) {
    return 'Use at least ' + MIN_PASSWORD + ' characters. Length matters more than symbols.';
  }
  if (value.length > 200) return 'That password is too long.';
  if (TOO_COMMON.has(value.toLowerCase())) return 'That password appears in breach lists. Pick another.';
  // Only worth checking when the local part is long enough to be meaningful:
  // for an address like a@b.co it is one letter, which would reject almost
  // every password ever typed.
  const local = normaliseEmail(email).split('@')[0];
  if (local.length >= 4 && value.toLowerCase().includes(local)) {
    return 'Do not put your email address in your password.';
  }
  return null;
}

module.exports = { checkEmail, checkPassword, normaliseEmail, MIN_PASSWORD, EMAIL };
