import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Service-role Supabase client.
 *
 * This key bypasses row-level security and must never reach the browser: the SPA talks only to this
 * API. The database is a read cache over chain data, so a lost or wrong row is recoverable by
 * replaying the indexer.
 */
export function createSupabase(url: string, serviceKey: string): SupabaseClient {
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { 'x-application-name': 'second-wind-api' } },
  });
}
