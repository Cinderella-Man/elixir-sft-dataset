# Promo Code System

Write me an Elixir context module called `PromoCodes` that manages promotional
discount codes and applies them to orders. It keeps its data in-memory in a
single supervised process (use a `GenServer` or `Agent`).

## Money & units

All monetary values in this system are **non-negative integers representing
cents** (so `$100.00` is `10_000`). Order totals, fixed discount amounts, and
returned discount amounts are all integer cents. Percentages are plain numbers
in the range `0..100` (e.g. `20` means "20% off").

## Starting the process

- `PromoCodes.start_link(opts)` starts the process and returns `{:ok, pid}`.
  - It must accept a `:clock` option: a zero-arity function that returns the
    current time as a `DateTime` (UTC). If not provided, default to
    `fn -> DateTime.utc_now() end`.
  - It must accept a `:name` option for process registration. If not provided,
    register under `__MODULE__` (the module acts as a named singleton).
  - It must be startable under a supervisor (provide a child spec — `use
    GenServer` / `use Agent` gives you one for free).

All the API functions below operate on the default (named `__MODULE__`)
instance — they take no explicit server argument.

## Creating codes: `create/1`

`PromoCodes.create(attrs)` takes a map and returns `{:ok, code}` or
`{:error, reason}`.

`attrs` fields:

- `:code` — required, a string, e.g. `"SAVE20"`. Codes are unique.
- `:type` — required, one of `:percentage`, `:fixed_amount`, `:free_shipping`.
- `:value` — required integer/number, interpreted per type:
  - `:percentage` → the percent off (`0..100`).
  - `:fixed_amount` → the amount off, in cents.
  - `:free_shipping` → the shipping amount waived, in cents.
- `:min_order_total` — optional integer cents, default `0`. The order total must
  be **greater than or equal to** this for the code to apply.
- `:max_uses` — optional integer, default `nil` (unlimited). Total number of
  successful applications across all users.
- `:max_uses_per_user` — optional integer, default `nil` (unlimited). Number of
  successful applications per user (see `:user_id` below).
- `:valid_from` — optional `DateTime`, default `nil` (no lower bound).
- `:valid_until` — optional `DateTime`, default `nil` (no upper bound).

Validation:

- If `:type` is not one of the three allowed atoms, return `{:error, :invalid_type}`.
- If a code with the same `:code` string already exists, return
  `{:error, :already_exists}`.

On success return `{:ok, code}` where `code` is a map/struct describing the
stored code.

## Applying codes: `apply/2` and `apply/3`

`PromoCodes.apply(code_string, order_total, opts \\ [])` attempts to apply the
code to an order and returns `{:ok, discount_amount}` (a non-negative integer in
cents) or `{:error, reason}`.

`opts` may contain `:user_id` (any term identifying the user). When present, it
is used for the per-user usage limit. Calls without a `:user_id` still count
toward the total `:max_uses` but are not tracked per user.

### Discount calculation (on success)

- `:percentage` → `round(order_total * value / 100)`.
  (e.g. 50% of `10_000` → `5_000`; 20% of `10_000` → `2_000`.)
- `:fixed_amount` → `min(value, order_total)` (you can never discount more than
  the order total).
- `:free_shipping` → `value` (the configured shipping amount waived).

### Checks and error reasons

Evaluate in this precedence order and return the **first** failure:

1. Unknown code → `{:error, :not_found}`.
2. Now is before `:valid_from` → `{:error, :not_yet_valid}`.
3. Now is after `:valid_until` → `{:error, :expired}`.
4. `order_total` is below `:min_order_total` → `{:error, :below_min_order}`.
5. Total successful uses already `>= :max_uses` → `{:error, :max_uses_exceeded}`.
6. This user's successful uses already `>= :max_uses_per_user` →
   `{:error, :max_uses_per_user_exceeded}`.

"Now" is obtained by calling the injected `:clock`. Boundaries are inclusive:
`now == valid_from` is valid (not yet-valid), `now == valid_until` is valid (not
expired), and `order_total == min_order_total` passes the minimum check.

### Usage accounting

Only a **successful** application consumes a use. A call that returns
`{:error, _}` (e.g. below minimum order) must not increment any usage counter.
On success, increment the total use count and, when a `:user_id` is given, that
user's per-user count.

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.