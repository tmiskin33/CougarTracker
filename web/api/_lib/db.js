// Storage for accounts and, once someone has one, their deadlines.
//
// This is the piece that turns "separate spaces" into "private data": with the
// rows on a server keyed by a verified session, one person's deadlines are no
// longer readable from another person's developer console.
'use strict';

const { neon } = require('@neondatabase/serverless');

// Built on first use rather than at import, so the module can be loaded (and
// tested) without a database URL present.
let client = null;
function sql(strings, ...values) {
  if (!client) {
    const url = process.env.DATABASE_URL || process.env.POSTGRES_URL;
    if (!url) throw new Error('No DATABASE_URL is set. Add a Neon (Postgres) database in Vercel.');
    client = neon(url);
  }
  return client(strings, ...values);
}

let ready = null;

// Created on first use rather than through a migration step, which is the right
// trade for a single-tenant personal app. Every statement is IF NOT EXISTS, so
// it is safe to run on every cold start.
function ensureSchema() {
  if (ready) return ready;
  ready = (async function () {
    await sql`CREATE EXTENSION IF NOT EXISTS pgcrypto`;
    await sql`
      CREATE TABLE IF NOT EXISTS users (
        id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        email        text UNIQUE NOT NULL,
        password_hash text NOT NULL,
        verified_at  timestamptz,
        created_at   timestamptz NOT NULL DEFAULT now()
      )`;
    await sql`
      CREATE TABLE IF NOT EXISTS verifications (
        token_hash text PRIMARY KEY,
        user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires_at timestamptz NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now()
      )`;
    await sql`
      CREATE TABLE IF NOT EXISTS sessions (
        token_hash text PRIMARY KEY,
        user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires_at timestamptz NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now()
      )`;
    await sql`
      CREATE TABLE IF NOT EXISTS user_data (
        user_id    uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        deadlines  jsonb NOT NULL DEFAULT '[]'::jsonb,
        settings   jsonb NOT NULL DEFAULT '{}'::jsonb,
        updated_at timestamptz NOT NULL DEFAULT now()
      )`;
    await sql`
      CREATE TABLE IF NOT EXISTS attempts (
        bucket     text NOT NULL,
        at         timestamptz NOT NULL DEFAULT now()
      )`;
    await sql`CREATE INDEX IF NOT EXISTS attempts_bucket_at ON attempts (bucket, at)`;
  })();
  return ready;
}

async function findUserByEmail(email) {
  await ensureSchema();
  const rows = await sql`SELECT * FROM users WHERE email = ${email} LIMIT 1`;
  return rows[0] || null;
}

async function findUserById(id) {
  await ensureSchema();
  const rows = await sql`SELECT * FROM users WHERE id = ${id} LIMIT 1`;
  return rows[0] || null;
}

async function createUser(email, passwordHash) {
  await ensureSchema();
  const rows = await sql`
    INSERT INTO users (email, password_hash) VALUES (${email}, ${passwordHash})
    RETURNING *`;
  return rows[0];
}

async function updatePassword(userId, passwordHash) {
  await ensureSchema();
  await sql`UPDATE users SET password_hash = ${passwordHash} WHERE id = ${userId}`;
}

// --- verification ---

async function createVerification(userId, tokenHash, expiresAt) {
  await ensureSchema();
  // One live verification link per account: issuing a new one retires the old.
  await sql`DELETE FROM verifications WHERE user_id = ${userId}`;
  await sql`
    INSERT INTO verifications (token_hash, user_id, expires_at)
    VALUES (${tokenHash}, ${userId}, ${expiresAt.toISOString()})`;
}

async function consumeVerification(tokenHash) {
  await ensureSchema();
  const rows = await sql`
    DELETE FROM verifications
    WHERE token_hash = ${tokenHash} AND expires_at > now()
    RETURNING user_id`;
  if (!rows[0]) return null;
  await sql`UPDATE users SET verified_at = now() WHERE id = ${rows[0].user_id}`;
  return rows[0].user_id;
}

// --- sessions ---

async function createSession(userId, tokenHash, expiresAt) {
  await ensureSchema();
  await sql`
    INSERT INTO sessions (token_hash, user_id, expires_at)
    VALUES (${tokenHash}, ${userId}, ${expiresAt.toISOString()})`;
}

async function findSession(tokenHash) {
  await ensureSchema();
  const rows = await sql`
    SELECT s.user_id, u.email, u.verified_at
    FROM sessions s JOIN users u ON u.id = s.user_id
    WHERE s.token_hash = ${tokenHash} AND s.expires_at > now()
    LIMIT 1`;
  return rows[0] || null;
}

async function deleteSession(tokenHash) {
  await ensureSchema();
  await sql`DELETE FROM sessions WHERE token_hash = ${tokenHash}`;
}

async function deleteAllSessions(userId) {
  await ensureSchema();
  await sql`DELETE FROM sessions WHERE user_id = ${userId}`;
}

// --- the user's own data ---

async function loadUserData(userId) {
  await ensureSchema();
  const rows = await sql`SELECT deadlines, settings FROM user_data WHERE user_id = ${userId}`;
  return rows[0] || { deadlines: [], settings: {} };
}

async function saveUserData(userId, deadlines, settings) {
  await ensureSchema();
  await sql`
    INSERT INTO user_data (user_id, deadlines, settings, updated_at)
    VALUES (${userId}, ${JSON.stringify(deadlines)}::jsonb, ${JSON.stringify(settings)}::jsonb, now())
    ON CONFLICT (user_id) DO UPDATE
      SET deadlines = EXCLUDED.deadlines,
          settings = EXCLUDED.settings,
          updated_at = now()`;
}

// --- throttling ---

// Counts recent attempts in a bucket and records this one. Slow and simple,
// which is fine: it only runs on sign-up and sign-in.
async function throttle(bucket, limit, windowSeconds) {
  await ensureSchema();
  await sql`DELETE FROM attempts WHERE at < now() - make_interval(secs => ${windowSeconds * 4})`;
  const rows = await sql`
    SELECT count(*)::int AS n FROM attempts
    WHERE bucket = ${bucket} AND at > now() - make_interval(secs => ${windowSeconds})`;
  const used = rows[0] ? rows[0].n : 0;
  await sql`INSERT INTO attempts (bucket) VALUES (${bucket})`;
  return used < limit;
}

module.exports = {
  ensureSchema, findUserByEmail, findUserById, createUser, updatePassword,
  createVerification, consumeVerification,
  createSession, findSession, deleteSession, deleteAllSessions,
  loadUserData, saveUserData, throttle
};
