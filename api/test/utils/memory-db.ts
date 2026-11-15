import type { SupabaseClient } from '@supabase/supabase-js';

type Row = Record<string, unknown>;

/**
 * A tiny in-memory stand-in for the Supabase query builder: just the methods the joiner and the
 * stores call, with the same chaining. It keeps the tests honest about upserts and filters without
 * a database, and it is never imported by `src`.
 */
export class MemoryDb {
  private readonly tables = new Map<string, Row[]>();

  seed(table: string, rows: Row[]): void {
    this.tables.set(
      table,
      rows.map((row) => ({ ...row })),
    );
  }

  rows(table: string): Row[] {
    return this.tables.get(table) ?? [];
  }

  from(table: string): MemoryQuery {
    if (!this.tables.has(table)) {
      this.tables.set(table, []);
    }
    return new MemoryQuery(this.tables.get(table) as Row[], table);
  }

  /** The production code takes a SupabaseClient; this is structurally close enough for tests. */
  asClient(): SupabaseClient {
    return this as unknown as SupabaseClient;
  }
}

type Result = { data: unknown; error: { message: string } | null; count?: number | null };

class MemoryQuery implements PromiseLike<Result> {
  private filters: ((row: Row) => boolean)[] = [];
  private orderBy: { column: string; ascending: boolean } | null = null;
  private max: number | null = null;
  private mode: 'select' | 'insert' | 'update' | 'upsert' = 'select';
  private patch: Row | null = null;
  private conflictKeys: string[] = [];
  private ignoreDuplicates = false;
  private single = false;
  private head = false;

  constructor(private readonly rows: Row[], private readonly table: string) {}

  select(_columns?: string, options?: { count?: string; head?: boolean }): this {
    if (options?.head) {
      this.head = true;
    }
    return this;
  }

  eq(column: string, value: unknown): this {
    this.filters.push((row) => row[column] === value);
    return this;
  }

  in(column: string, values: readonly unknown[]): this {
    this.filters.push((row) => values.includes(row[column]));
    return this;
  }

  lt(column: string, value: unknown): this {
    this.filters.push((row) => Number(row[column]) < Number(value));
    return this;
  }

  order(column: string, options?: { ascending?: boolean }): this {
    this.orderBy = { column, ascending: options?.ascending ?? true };
    return this;
  }

  limit(count: number): this {
    this.max = count;
    return this;
  }

  update(patch: Row): this {
    this.mode = 'update';
    this.patch = patch;
    return this;
  }

  insert(row: Row): this {
    this.mode = 'insert';
    this.patch = row;
    return this;
  }

  upsert(row: Row, options?: { onConflict?: string; ignoreDuplicates?: boolean }): this {
    this.mode = 'upsert';
    this.patch = row;
    this.conflictKeys = (options?.onConflict ?? 'id').split(',').map((key) => key.trim());
    this.ignoreDuplicates = options?.ignoreDuplicates ?? false;
    return this;
  }

  maybeSingle(): Promise<Result> {
    this.single = true;
    return Promise.resolve(this.run());
  }

  then<TResult1 = Result, TResult2 = never>(
    onfulfilled?: ((value: Result) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    return Promise.resolve(this.run()).then(onfulfilled, onrejected);
  }

  private matching(): Row[] {
    return this.rows.filter((row) => this.filters.every((filter) => filter(row)));
  }

  private run(): Result {
    const matched = this.matching();

    if (this.mode === 'update') {
      for (const row of matched) {
        Object.assign(row, this.patch);
      }
      return { data: null, error: null };
    }

    if (this.mode === 'insert') {
      this.rows.push({ ...this.patch });
      return { data: null, error: null };
    }

    if (this.mode === 'upsert') {
      const patch = this.patch ?? {};
      const existing = matched.find((row) =>
        this.conflictKeys.every((key) => row[key] === patch[key]),
      );
      if (existing) {
        if (!this.ignoreDuplicates) {
          Object.assign(existing, patch);
        }
      } else {
        this.rows.push({ ...patch });
      }
      return { data: null, error: null };
    }

    if (this.head) {
      return { data: null, error: null, count: matched.length };
    }

    let result = [...matched];
    if (this.orderBy) {
      const { column, ascending } = this.orderBy;
      result.sort((a, b) => (Number(a[column]) - Number(b[column])) * (ascending ? 1 : -1));
    }
    if (this.max !== null) {
      result = result.slice(0, this.max);
    }

    return { data: this.single ? (result[0] ?? null) : result, error: null };
  }

  /** Keeps `table` referenced so the helper reads as a query builder in stack traces. */
  toString(): string {
    return `MemoryQuery(${this.table})`;
  }
}
