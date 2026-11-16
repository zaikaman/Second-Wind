-- The health a loan had on the block before it was liquidated. It is captured when the liquidation
-- log is indexed, because reading that state later depends on the RPC node's retention window.
alter table claims
  add column health_before numeric(78,0);
