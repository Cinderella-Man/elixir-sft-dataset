# Stackable Promo Code System

Write me an Elixir context module called `StackablePromoCodes` that manages
promotional discount codes and applies **several codes at once** to a single
order. It keeps its data in-memory in a single supervised process (use a
`GenServer` or `Agent`).

## Money & units

All monetary values are **non-negative integers representing cents** (so
`$100.00` is `10_000`). Order totals, fixed discount amounts, and returned
discount amounts are all integer cents. Percentages are plain numbers in the
range `0..100`.

## Starting the process

- `StackablePromoCodes.start_link(opts)` starts the process and returns
  `{:ok, pid}`.
  - It must accept a `:clock` option: a zero-arity function returning the
    current time as a UTC `DateTime`. Default `fn -> DateTime.utc_now() end`.
  - It must accept a `:name` option. Default `__MODULE__` (named singleton).
  - It must be startable under a supervisor.

All API functions operate on the default (`__MODULE__`) instance.

## Creating codes: `create/1`

`StackablePromoCodes.create(attrs)` takes a map and returns `{:ok, code}` or
`{:error, reason}`.

`attrs` fields:

- `:code` — required string, unique.
- `:type` — required, one of `:percentage`, `:fixed_amount`, `:free_shipping`.
- `:value` — required number, interpreted per type (percent off / cents off /
  shipping cents waived).
- `:min_order_total` — optional integer cents, default `0` (order total must be
  `>=` this).
- `:max_uses` — optional integer, default `nil` (unlimited total applications).
- `:max_uses_per_user` — optional integer, default `nil`.
- `:valid_from` / `:valid_until` — optional `DateTime`, default `nil`.

Validation:

- `:type` not one of the three atoms → `{:error, :invalid_type}`.
- Duplicate `:code` → `{:error, :already_exists}`.

## Applying codes: `apply_codes/2` and `apply_codes/3`

`StackablePromoCodes.apply_codes(codes, order_total, opts \\ [])` where `codes`
is a **list of code strings**. `opts` may contain `:user_id`.

An empty list returns `{:error, :no_codes}`. Otherwise it always returns
`{:ok, result}` where `result` is a map:

```
%{
  total_discount: integer,          # cents, never exceeds order_total
  final_total:    integer,          # order_total - total_discount
  applied:  [%{code: str, type: atom, discount: integer}, ...],
  rejected: [%{code: str, reason: atom}, ...]
}
```

### Per-code validity (first failure wins, base precedence)

For each code, in this order: unknown → `:not_found`; before `:valid_from` →
`:not_yet_valid`; after `:valid_until` → `:expired`; below `:min_order_total` →
`:below_min_order`; total uses `>= :max_uses` → `:max_uses_exceeded`; this
user's uses `>= :max_uses_per_user` → `:max_uses_per_user_exceeded`. A code
string appearing more than once in `codes` → the later occurrence is rejected
with `:duplicate_in_order`. Boundaries are inclusive.

### Stacking rules

Among the codes that pass validity:

- **At most one percentage code** may apply: the one with the highest `value`
  wins; the rest are rejected with `:percentage_already_applied`.
- **At most one free_shipping code** may apply: the first (in list order) wins;
  the rest are rejected with `:free_shipping_already_applied`.
- Any number of `:fixed_amount` codes may apply.

### Discount computation

Start `remaining = order_total`. Apply, in this order, capping each discount at
the current `remaining` and subtracting it:

1. the chosen percentage code → `round(order_total * value / 100)`,
2. the chosen free_shipping code → `value`,
3. each fixed_amount code (in list order) → `value`.

`total_discount = order_total - remaining`. Every code placed in `applied`
consumes a use (increment total, and per-user when `:user_id` is given). Codes
in `rejected` consume nothing.

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.