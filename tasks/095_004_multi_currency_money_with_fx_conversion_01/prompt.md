# Multi-Currency Money with FX Conversion

Write me an Elixir module called `Money` that handles multi-currency amounts
(stored as **integer cents**) and can **convert between currencies** and sum a
mixed-currency collection using an exchange-rate table. Same-currency
arithmetic stays strict; cross-currency work goes explicitly through conversion.

## The struct

`Money` must be a struct with exactly two fields:

- `:amount` — an integer number of cents (may be negative)
- `:currency` — a currency atom such as `:USD`, `:EUR`, `:GBP`

## Rate tables

Exchange rates are a plain map from a currency atom to a **float rate**: the
value of one unit of that currency expressed in a common base.

```elixir
rates = %{USD: 1.0, EUR: 1.10, GBP: 1.25}
```

To convert an amount from currency `from` to currency `to`, compute
`round(amount * rates[from] / rates[to])`. Converting to the same currency
returns the same amount — but the rate lookup still applies, so a currency
missing from `rates` raises even when the source and target are equal.

## Public API

### `Money.new(cents, currency)`

Creates a money struct. `cents` is an **integer**, `currency` is an **atom**.
Raise `ArgumentError` if `cents` is not an integer or `currency` is not an atom.

### `Money.add(a, b)` / `Money.subtract(a, b)`

Add / subtract two money values. **Both must have the same currency.** Returns a
new `Money` struct. If the currencies differ, raise `ArgumentError` — these
functions never auto-convert.

### `Money.multiply(money, factor)`

Multiplies by a **number** (integer or float), rounding the resulting cents to
the nearest whole cent (round halves away from zero). Same currency.

### `Money.split(money, n)`

Divides evenly among `n` parties (`n` a **positive integer**), distributing the
remainder to the first `rem(amount, n)` parties so shares sum back to the
original. Returns a list of `n` `Money` structs. Raise `ArgumentError` if `n` is
not a positive integer.

### `Money.convert(money, to_currency, rates)`

Converts `money` into `to_currency` using the rate table, rounding the result to
the nearest whole cent. Returns a new `Money` struct in `to_currency`.

```elixir
rates = %{USD: 1.0, EUR: 1.10, GBP: 1.25}

Money.convert(Money.new(100, :USD), :EUR, rates)
# => %Money{amount: 91, currency: :EUR}   (100 * 1.0 / 1.10 = 90.9 -> 91)

Money.convert(Money.new(100, :EUR), :USD, rates)
# => %Money{amount: 110, currency: :USD}  (100 * 1.10 / 1.0 = 110)

Money.convert(Money.new(80, :USD), :USD, rates)
# => %Money{amount: 80, currency: :USD}   (same currency)
```

If either the source or target currency is missing from `rates`, raise
`ArgumentError`. This applies even when the source and target currency are the
same: converting an unknown currency to itself still raises.

### `Money.total(list_of_money, currency, rates)`

Converts every `Money` in the list into `currency` (rounding each conversion
independently) and sums them into a single `Money` struct in `currency`. An
empty list totals to zero in `currency`.

```elixir
Money.total([Money.new(100, :USD), Money.new(100, :EUR)], :USD, rates)
# => %Money{amount: 210, currency: :USD}   (100 USD + 110 USD)
```

## Constraints

- Single file, module named `Money`.
- Use only the Elixir/OTP standard library — no external dependencies.
- Do not use floats for storage; only `multiply/2`, `convert/3`, and `total/3`
  may involve floats, and their results must be rounded back to integer cents.
