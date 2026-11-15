-- Second Wind cache schema. Authority is on chain; every row here is derived and replayable.

create type claim_status   as enum ('pending', 'partial', 'settled', 'failed');
create type branch_status  as enum ('pending', 'confirmed', 'failed');
create type branch_kind    as enum ('relief', 'cash', 'dispatch', 'registration');

create table policies_mirror (
  policy_id          numeric(78,0) primary key,
  borrower           text        not null,
  market_id          text        not null,
  coverage_cap       numeric(38,18) not null,
  cash_ceiling       numeric(38,18) not null,
  relief_ceiling     numeric(38,18) not null,
  relief_used        numeric(38,18) not null default 0,
  cash_paid          numeric(38,18) not null default 0,
  relief_share_bps   integer     not null,
  premium_per_second numeric(38,18) not null,
  paid_through       bigint      not null,
  target_health      numeric(38,18) not null,
  lltv               numeric(38,18) not null default 0,
  cash_destination   text        not null,
  status             text        not null,
  created_at         timestamptz not null,
  updated_at         timestamptz not null default now()
);

create table claims (
  run_id            text primary key,
  policy_id         numeric(78,0) not null references policies_mirror(policy_id),
  borrower          text        not null,
  market_id         text        not null,
  origin_chain_id   integer     not null,
  origin_tx_hash    text        not null,
  origin_block      bigint      not null,
  origin_log_index  integer     not null,
  origin_block_time timestamptz not null,
  fee_amount        numeric(38,18) not null,
  cash_limit        numeric(38,18) not null,
  relief_limit      numeric(38,18) not null,
  mode              text        not null,
  status            claim_status not null default 'pending',
  decided_at        timestamptz not null,
  detected_at       timestamptz not null default now(),
  settled_at        timestamptz,
  total_latency_ms  integer
);

create table claim_events (
  id           bigserial primary key,
  run_id       text not null references claims(run_id) on delete cascade,
  chain_id     integer not null,
  kind         branch_kind not null,
  status       branch_status not null default 'pending',
  tx_hash      text,
  block_number bigint,
  block_time   timestamptz,
  amount       numeric(38,18),
  detail       jsonb not null default '{}'::jsonb,
  error        text,
  created_at   timestamptz not null default now(),
  unique (run_id, chain_id, kind)
);

create table latency_samples (
  id                bigserial primary key,
  run_id            text references claims(run_id) on delete cascade,
  branch            branch_kind not null,
  trial             integer not null,
  origin_block_time timestamptz not null,
  dispatch_time     timestamptz,
  confirm_block_time timestamptz,
  latency_ms        integer not null,
  created_at        timestamptz not null default now()
);

create table indexer_cursor (
  chain_id   integer primary key,
  last_block bigint not null,
  updated_at timestamptz not null default now()
);

create index on claims (borrower, origin_block_time desc);
create index on claims (status) where status <> 'settled';
create index on claim_events (run_id, chain_id);
create index on latency_samples (trial, branch);
