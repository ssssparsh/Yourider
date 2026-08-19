/**
 * Yourider CRM domain types.
 *
 * These mirror the PostgreSQL schema in src/db/migrations/, which is the
 * authoritative definition. When the two disagree, the database is right and
 * these files are the bug — src/crm/types/verify.ts catches that drift in CI.
 */

export * from './scalars.js';
export * from './enums.js';
export * from './entities.js';
export * from './consent.js';
export * from './attachments.js';
export * from './pricing.js';
export * from './automation.js';
export * from './verify.js';
