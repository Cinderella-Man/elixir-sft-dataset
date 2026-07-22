# Budget-Capped Promo Code System

Write me an Elixir context module called `BudgetPromoCodes` that manages
promotional discount codes with a total **discount budget** — a fixed pool of
cents a code may dispense across all applications. When an application would draw
more than the remaining budget, the discount is **clipped** to what is left. It
keeps its data in-memory in a single supervised process (use a `GenServer` or
`Agent`).

## Money & units

All monetary values are **non-negative integers representing cents** (so
`$100.00` is `10_000`). Percentages are plain numbers in the range `0..100`.

## Starting the process

- `BudgetPromoCodes.start_link(opts)` returns `{:ok, pid}`.
  - `:clock` — a zero-arity function returning the current UTC `DateTime`.
    Default `fn -> DateTime.utc_now() end`.
  - `:name` — registration name. Default `__MODULE__` (named singleton).
  - Must be startable under a supervisor.

All API functions operate on the default (`__MODULE__`) instance.

## Creating codes: `create/1`

`BudgetPromoCodes.create(attrs)` returns `{:ok, code}` or `{:error, reason}`.

`attrs` fields:

- `:code` — required string, unique.
- `:type` — required, one of `:percentage`, `:fixed_amount`, `:free_shipping`.
- `:value` — required number, interpreted per type (percent off / cents off /
  shipping cents waived).
- `:budget` — optional integer cents, default `nil` (unlimited). The total
  discount the code may ever dispense, summed across all successful
  applications.
- `:min_order_total` — optional integer cents, default `0`.
- `:max_uses` — optional integer, default `nil` (unlimited).
- `:valid_from` / `:valid_until` — optional `DateTime`, default `nil`.

Validation:

- `:type` not one of the three atoms → `{:error, :invalid_type}`.
- Duplicate `:code` → `{:error, :already_exists}`.

## Applying: `apply_code/2` and `apply_code/3`

`BudgetPromoCodes.apply_code(code_string, order_total, opts \\ [])` returns
`{:ok, discount}` or `{:error, reason}`. `opts` may contain `:user_id` (used only
for usage counting, not budget).

### Raw discount (before budget clipping)

- `:percentage` → `round(order_total * value / 100)`.
- `:fixed_amount` → `min(value, order_total)`.
- `:free_shipping` → `value`.

### Checks and precedence

Evaluate in this order and return the **first** failure:

1. Unknown code → `:not_found`.
2. Now before `:valid_from` → `:not_yet_valid`.
3. Now after `:valid_until` → `:expired`.
4. `order_total` below `:min_order_total` → `:below_min_order`.
5. Total uses `>= :max_uses` → `:max_uses_exceeded`.
6. Budget is set and the remaining budget is `<= 0` → `:budget_exhausted`.

Boundaries are inclusive. On success, the returned `discount` is
`min(raw_discount, remaining_budget)` when a budget is set (otherwise
`raw_discount`). The dispensed amount is added to the code's running total and
the use counters are incremented. A failed application changes nothing.

## Inspection

- `BudgetPromoCodes.remaining_budget(code_string)` → `{:ok, :unlimited}` (no
  budget), `{:ok, cents}`, or `{:error, :not_found}`.
- `BudgetPromoCodes.dispensed(code_string)` → `{:ok, cents}` (total discount
  dispensed so far) or `{:error, :not_found}`.

## Constraints

Give me the complete module in a single file (`solution.ex`). Use only the OTP
standard library — no external dependencies.