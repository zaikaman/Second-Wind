-- Token amounts are stored as raw 18-decimal integers, exactly as the contracts emit them. The
-- original `numeric(38,18)` columns top out at 1e20, so a 5,000 token cap (5e21 wei) overflowed and
-- the indexer dropped the row. `numeric(78,0)` matches the EVM word size and keeps full precision
-- without ever rounding a wei away.

alter table policies_mirror
  alter column coverage_cap       type numeric(78,0),
  alter column cash_ceiling       type numeric(78,0),
  alter column relief_ceiling     type numeric(78,0),
  alter column relief_used        type numeric(78,0),
  alter column cash_paid          type numeric(78,0),
  alter column premium_per_second type numeric(78,0),
  alter column target_health      type numeric(78,0),
  alter column lltv               type numeric(78,0);

alter table claims
  alter column fee_amount   type numeric(78,0),
  alter column cash_limit   type numeric(78,0),
  alter column relief_limit type numeric(78,0);

alter table claim_events
  alter column amount type numeric(78,0);
