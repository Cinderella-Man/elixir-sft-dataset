# Multi-Currency Money Module

Write me an Elixir module called `Money` that handles multi-currency arithmetic
safely. All amounts are stored internally as **integer cents** to avoid any
floating-point representation problems.

## The struct

`Money` must be a struct with exactly two fields:

- `:amount` — an integer number of cents (may be negative, e.g. for debts)
- `:currency` — an atom such as `:USD`, `:EUR`, `:JPY`

## Public API

### `Money.new(cents, currency)`

Creates a money struct. `cents` is an **integer** (the amount in cents) and
`currency` is an **atom**.

```elixir
Money.new(100, :USD)   # => %Money{amount: 100, currency: :USD}   (== $1.00)
Money.new(1000, :USD)  # => %Money{amount: 1000, currency: :USD}  (== $10.00)
```

If `cents` is not an integer, or `currency` is not an atom, raise
`ArgumentError`.

### `Money.add(a, b)`

Adds two money values. **Both must have the same currency.** Returns a new
`Money` struct on success. If the currencies differ, raise `ArgumentError`.

```elixir
Money.add(Money.new(100, :USD), Money.new(250, :USD))
# => %Money{amount: 350, currency: :USD}
```

### `Money.subtract(a, b)`

Subtracts `b` from `a`. **Both must have the same currency.** Returns a new
`Money` struct (the result may be negative). If the currencies differ, raise
`ArgumentError`.

```elixir
Money.subtract(Money.new(500, :USD), Money.new(200, :USD))
# => %Money{amount: 300, currency: :USD}
```

### `Money.multiply(money, factor)`

Multiplies a money value by a **number** (integer or float). The resulting cent
amount must be rounded to the nearest whole cent, rounding halves away from zero
(this is exactly what Elixir's `round/1` does). Returns a new `Money` struct with
the same currency. The stored `:amount` is always an integer, even when the
factor is a float.

```elixir
Money.multiply(Money.new(100, :USD), 3)      # => %Money{amount: 300, currency: :USD}
Money.multiply(Money.new(100, :USD), 0.1)    # => %Money{amount: 10,  currency: :USD}
Money.multiply(Money.new(101, :USD), 0.5)    # => %Money{amount: 51,  currency: :USD}  (50.5 -> 51)
Money.multiply(Money.new(-101, :USD), 0.5)   # => %Money{amount: -51, currency: :USD}  (-50.5 -> -51)
```

### `Money.split(money, n)`

Divides a money value evenly among `n` parties, where `n` is a **positive
integer**. Returns a **list of `n` `Money` structs**. Because integer cents may
not divide evenly, distribute the remainder fairly: the first
`rem(amount, n)` parties each receive **one extra cent**. This guarantees the
returned amounts always **sum back to the original amount**.

```elixir
Money.split(Money.new(1000, :USD), 3)
# => [%Money{amount: 334, currency: :USD},
#     %Money{amount: 333, currency: :USD},
#     %Money{amount: 333, currency: :USD}]
# ($10.00 split three ways -> $3.34, $3.33, $3.33; sums back to $10.00)

Money.split(Money.new(900, :USD), 3)
# => [%Money{amount: 300, ...}, %Money{amount: 300, ...}, %Money{amount: 300, ...}]

Money.split(Money.new(2, :USD), 3)
# => [%Money{amount: 1, ...}, %Money{amount: 1, ...}, %Money{amount: 0, ...}]
```

For a **negative** amount the remainder is distributed the same way but as a
negative extra cent, so the shares still **sum back to the original amount** and
no two shares differ by more than one cent (the exact ordering of shares for
negative amounts is unspecified):

```elixir
Money.split(Money.new(-1000, :USD), 3)
# => three parts summing to -1000, each within one cent of the others
```

Every returned struct keeps the original currency. If `n` is not a positive
integer (including a float such as `3.0`, or a non-numeric value), raise
`ArgumentError`.

## Constraints

- Single file, module named `Money`.
- Use only the Elixir/OTP standard library — no external dependencies.
- Do not use floats for storage; only `multiply/2` may involve a float factor,
  and its result must be rounded back to an integer cent count.
