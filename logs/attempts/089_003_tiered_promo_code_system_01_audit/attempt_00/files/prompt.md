# Tiered Promo Code System

Write me an Elixir context module called `TieredPromoCodes` that manages
promotional codes whose discount **scales with the order total** via configured
tiers. It keeps its data in-memory in a single supervised process (use a
`GenServer` or `Agent`).

## Money & units

All monetary values are **non-negative integers representing cents** (so
`$100.00` is `10_000`). Percentages are plain numbers in the range `0..100`.

## Starting the process

- `TieredPromoCodes.start_link(opts)` returns `{:ok, pid}`.
  - `:clock` — a zero-arity function returning the current UTC `DateTime`.
    Default `fn -> DateTime.utc_now() end`.
  - `:name` — registration name. Default `__MODULE__` (named singleton).
  - Must be startable under a supervisor.

All API functions operate on the default (`__MODULE__`) instance.

## Creating codes: `create/1`

`TieredPromoCodes.create(attrs)` returns `{:ok, code}` or `{:error, reason}`.

`attrs` fields:

- `:code` — required string, unique.
- `:tiers` — required non-empty list of tier maps, each
  `%{threshold: cents, type: :percentage | :fixed_amount, value: number}`.
  A tier applies when `order_total >= threshold`.
- `:max_uses` — optional integer, default `nil` (unlimited).
- `:max_uses_per_user` — optional integer, default `nil`.
- `:valid_from` / `:valid_until` — optional `DateTime`, default `nil`.

Validation:

- Not a binary `:code` → `{:error, :invalid_code}`.
- `:tiers` not a non-empty list, or any tier malformed, or thresholds not
  **strictly ascending** → `{:error, :invalid_tiers}`. A tier is malformed if
  `threshold` is not a non-negative integer, `type` is not one of the two
  allowed atoms, `value` is not a number, or (for `:percentage`) `value` is
  outside `0..100`, or (for either) `value` is negative.
- Duplicate `:code` → `{:error, :already_exists}`.

## Selecting a tier

For a given `order_total`, the applicable tier is the one with the **highest
`threshold` that is `<= order_total`**. If no tier qualifies (the order is below
the smallest threshold), that condition is reported as `:below_min_order`.

Discount for the chosen tier:

- `:percentage` → `round(order_total * value / 100)`.
- `:fixed_amount` → `min(value, order_total)`.

## Previewing: `preview/2`

`TieredPromoCodes.preview(code_string, order_total)` returns
`{:ok, discount, tier_index}` (0-based index into the tier list) **without
consuming a use** and without checking the time window or usage limits, or
`{:error, :not_found}` / `{:error, :below_min_order}`.

## Applying: `apply_code/2` and `apply_code/3`

`TieredPromoCodes.apply_code(code_string, order_total, opts \\ [])` returns
`{:ok, discount}` or `{:error, reason}`. `opts` may contain `:user_id`.

Evaluate in this precedence order and return the **first** failure:

1. Unknown code → `:not_found`.
2. Now before `:valid_from` → `:not_yet_valid`.
3. Now after `:valid_until` → `:expired`.
4. No tier qualifies for `order_total` → `:below_min_order`.
5. Total uses `>= :max_uses` → `:max_uses_exceeded`.
6. This user's uses `>= :max_uses_per_user` → `:max_uses_per_user_exceeded`.

Boundaries are inclusive. Only a successful application consumes a use
(increment total, and per-user when `:user_id` is given).

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.