# Weighted Allocation Money Module

Write me an Elixir module called `Money` that handles multi-currency
arithmetic safely and can divide a monetary amount among parties using
**arbitrary integer weights** (not just an even split). All amounts are stored
internally as **integer cents** to avoid any floating-point representation
problems.

## The struct

`Money` must be a struct with exactly two fields:

- `:amount` — an integer number of cents (may be negative, e.g. for debts)
- `:currency` — an atom such as `:USD`, `:EUR`, `:JPY`

## Public API

### `Money.new(cents, currency)`

Creates a money struct. `cents` is an **integer** (the amount in cents) and
`currency` is an **atom**.

```elixir
Money.new(100, :USD)   # => %Money{amount: 100, currency: :USD}
```

If `cents` is not an integer, or `currency` is not an atom, raise
`ArgumentError`.

### `Money.add(a, b)` / `Money.subtract(a, b)`

Add / subtract two money values. **Both must have the same currency.** Returns a
new `Money` struct. If the currencies differ, raise `ArgumentError`.

```elixir
Money.add(Money.new(100, :USD), Money.new(250, :USD))
# => %Money{amount: 350, currency: :USD}

Money.subtract(Money.new(500, :USD), Money.new(200, :USD))
# => %Money{amount: 300, currency: :USD}
```

### `Money.multiply(money, factor)`

Multiplies a money value by a **number** (integer or float). The resulting cent
amount is rounded to the nearest whole cent, rounding halves away from zero
(Elixir's `round/1`). Returns a new `Money` struct with the same currency.

```elixir
Money.multiply(Money.new(101, :USD), 0.5)  # => %Money{amount: 51, currency: :USD}
```

### `Money.allocate(money, ratios)`

Divides a money value among parties according to a list of **integer weights**.
`ratios` is a **non-empty list of non-negative integers** whose sum is
**strictly positive**. Returns a **list of `Money` structs**, one per weight.

Each party's base share is `div(amount * ratio, total_ratio)` (truncating
integer division). Because integer cents may not divide cleanly, there will be a
leftover **remainder** (`amount - sum(base_shares)`); distribute it **one cent at
a time to the earliest parties**, in list order. When `amount` is negative the
leftover is negative, so distribute **one negative cent** at a time instead. This
guarantees the returned amounts always **sum back to the original amount**.

```elixir
Money.allocate(Money.new(100, :USD), [3, 7])
# => [%Money{amount: 30, currency: :USD}, %Money{amount: 70, currency: :USD}]

Money.allocate(Money.new(10, :USD), [1, 1, 1, 1])
# => [%Money{amount: 3, ...}, %Money{amount: 3, ...},
#     %Money{amount: 2, ...}, %Money{amount: 2, ...}]   (remainder 2 -> first two parties)

Money.allocate(Money.new(1000, :USD), [1, 1, 1])
# => [%Money{amount: 334, ...}, %Money{amount: 333, ...}, %Money{amount: 333, ...}]
```

Every returned struct keeps the original currency. If `ratios` is not a
non-empty list of non-negative integers, or its sum is not strictly positive,
raise `ArgumentError`.

### `Money.split(money, n)`

Convenience wrapper: splits a money value evenly among `n` parties, where `n` is
a **positive integer**. Equivalent to allocating with `n` equal weights. Returns
a list of `n` `Money` structs summing back to the original amount. If `n` is not
a positive integer, raise `ArgumentError`.

```elixir
Money.split(Money.new(1000, :USD), 3)
# => [%Money{amount: 334, ...}, %Money{amount: 333, ...}, %Money{amount: 333, ...}]
```

## Constraints

- Single file, module named `Money`.
- Use only the Elixir/OTP standard library — no external dependencies.
- Do not use floats for storage; only `multiply/2` may involve a float factor,
  and its result must be rounded back to an integer cent count.