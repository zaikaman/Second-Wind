import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

export type Cell = string | number | bigint | boolean | null;

/** Prints rows as an aligned console table. Evidence is easier to read than a wall of JSON. */
export function printTable(rows: Record<string, Cell>[], columns?: string[]): void {
  if (rows.length === 0) {
    console.log('(no rows)');
    return;
  }

  const keys = columns ?? Object.keys(rows[0] ?? {});
  const widths = keys.map((key) =>
    Math.max(key.length, ...rows.map((row) => formatCell(row[key]).length)),
  );

  const header = keys.map((key, index) => key.padEnd(widths[index] ?? key.length)).join('  ');
  console.log(header);
  console.log(keys.map((key, index) => '-'.repeat(widths[index] ?? key.length)).join('  '));
  for (const row of rows) {
    console.log(keys.map((key, index) => formatCell(row[key]).padEnd(widths[index] ?? 0)).join('  '));
  }
}

function formatCell(value: Cell | undefined): string {
  if (value === undefined || value === null) {
    return '—';
  }
  return String(value);
}

/** Writes pretty-printed JSON, creating parent directories. Used for evidence artifacts. */
export function writeJsonEvidence(path: string, data: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(data, jsonReplacer, 2)}\n`, 'utf8');
}

function jsonReplacer(_key: string, value: unknown): unknown {
  return typeof value === 'bigint' ? value.toString() : value;
}
