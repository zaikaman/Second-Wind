import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { REPO_ROOT } from './env.js';

export type Hex = `0x${string}`;

export type AddressBook = {
  base: Record<string, Hex>;
  unichain: Record<string, Hex>;
  lasna: Record<string, Hex>;
};

/** Path to the file the deploy scripts write. */
export const ADDRESSES_PATH = resolve(REPO_ROOT, 'ops/addresses.json');

/**
 * Reads `ops/addresses.json`. Fails loudly when the file or a key is missing: every ops script
 * depends on addresses written by the deploy step, and a silent zero address would send a
 * transaction to `0x0`.
 */
export function readAddressBook(path = ADDRESSES_PATH): AddressBook {
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    throw new Error(`Missing ${path}. Run the deploy scripts first (see ops/docs/runbook.md).`);
  }

  const parsed = JSON.parse(raw) as Partial<AddressBook>;
  return {
    base: parsed.base ?? {},
    unichain: parsed.unichain ?? {},
    lasna: parsed.lasna ?? {},
  };
}

/** One address, with a loud failure when it was never recorded. */
export function requireAddress(
  book: AddressBook,
  chain: keyof AddressBook,
  key: string,
): Hex {
  const value = book[chain]?.[key];
  if (!value) {
    throw new Error(`Missing ${chain}.${key} in ${ADDRESSES_PATH}. Run the deploy scripts in order.`);
  }
  return value;
}
