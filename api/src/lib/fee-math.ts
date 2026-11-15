/**
 * The penalty and split, mirroring `contracts/src/libraries/FeeMath.sol`. The chain is
 * authoritative; this copy exists so the indexer can record the fee a liquidation implies without
 * an extra RPC read, and it is asserted against the contract's numbers in the unit tests.
 */
const WAD = 10n ** 18n;
const BPS = 10_000n;
const LIF_CAP = 1_150_000_000_000_000_000n; // 1.15e18
const LIF_PENALTY_FACTOR = 300_000_000_000_000_000n; // 0.3e18

/** Morpho's liquidation incentive factor for an LLTV, capped at 1.15. */
export function lif(lltv: bigint): bigint {
  const penaltyFactor = (LIF_PENALTY_FACTOR * (WAD - lltv)) / WAD;
  const computed = (WAD * WAD) / (WAD - penaltyFactor);
  return computed > LIF_CAP ? LIF_CAP : computed;
}

/** The penalty a liquidator paid on top of the repaid debt, floored. */
export function penalty(repaidAssets: bigint, lltv: bigint): bigint {
  const incentive = lif(lltv);
  if (incentive <= WAD) {
    return 0n;
  }
  return (repaidAssets * (incentive - WAD)) / WAD;
}

/** Splits a fee into cash and relief, both floored so the two never exceed the fee. */
export function split(fee: bigint, reliefShareBps: number): { cash: bigint; relief: bigint } {
  const share = BigInt(reliefShareBps);
  return {
    relief: (fee * share) / BPS,
    cash: (fee * (BPS - share)) / BPS,
  };
}
