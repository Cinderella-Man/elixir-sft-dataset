# Currency-Precision Money Module

Write me an Elixir module called `Money` that handles multi-currency
arithmetic where **each currency has its own number of decimal places** (its
minor-unit exponent). Amounts are stored internally as **integer minor units**
(cents for USD, whole yen for JPY, thousandths of a dinar for BHD) to avoid any
floating-point representation problems.

## Supported currencies and their exponents

Your module must know these currencies and exponents:

| currency | exponent | example                         |
|----------|----------|---------------------------------|
| `:USD`   | 2        | `12345` minor units = `123.45`  |
| `:EUR`   | 2        | `12345` = `123.45`              |
| `:GBP`   | 2        | `12345` = `123.45`              |
| `:JPY`   | 0        | `500` = `500`                   |
| `:KWD`   | 3        | `1234567` = `1234.567`          |
| `:BHD`   | 3        | `1234567` = `1234.567`          |

## The struct

`Money` must be a struct with exactly two fields:

- `:amount` — an integer number of **minor units** (may be negative)
- `:currency` — a supported currency atom

## Public API

### `Money.new(minor_units, currency)`

Creates a money struct directly from an **integer** number of minor units and a
**supported currency** atom. If `minor_units` is not an integer, or `currency`
is not a supported currency, raise `ArgumentError`.

```elixir
Money.new(12345, :USD)  # => %Money{amount: 12345, currency: :USD}   (== 123.45)
Money.new(500, :JPY)    # => %Money{amount: 500, currency: :JPY}     (== 500)
Money.new(100, :XYZ)    # raises ArgumentError (unknown currency)
```

### `Money.from_major(major, currency)`

Creates a money struct from a **major** amount (a number — integer or float,
e.g. dollars/euros/yen) by scaling to minor units using the currency's exponent
and rounding to the nearest whole minor unit (round halves away from zero).

```elixir
Money.from_major(12.34, :USD)  # => %Money{amount: 1234, currency: :USD}
Money.from_major(500, :JPY)    # => %Money{amount: 500,  currency: :JPY}
Money.from_major(1.2345, :BHD) # => %Money{amount: 1234, currency: :BHD}  (1.2345 -> 1234.5 -> 1235? no: 1.2345*1000=1234.5 -> 1235)
```

(`from_major(1.2345, :BHD)` scales `1.2345 * 1000 = 1234.5` and rounds to
`1235`.) Raise `ArgumentError` for a non-number `major` or an unsupported
currency.

### `Money.add(a, b)` / `Money.subtract(a, b)`

Add / subtract two money values. **Both must have the same currency.** Returns a
new `Money` struct. If the currencies differ, raise `ArgumentError`.

### `Money.multiply(money, factor)`

Multiplies by a **number** (integer or float). The resulting minor-unit amount
is rounded to the nearest whole minor unit (round halves away from zero). Same
currency.

### `Money.split(money, n)`

Divides a money value evenly among `n` parties (`n` a **positive integer**),
working in whole minor units. Returns a **list of `n` `Money` structs**;
distribute the remainder one minor unit at a time to the first `rem(amount, n)`
parties so the shares always sum back to the original amount. Raise
`ArgumentError` if `n` is not a positive integer.

```elixir
Money.split(Money.new(1000, :JPY), 3)
# => [%Money{amount: 334, ...}, %Money{amount: 333, ...}, %Money{amount: 333, ...}]
```

### `Money.exponent(currency)`

Returns the integer exponent for a supported currency, or raises `ArgumentError`.

### `Money.to_string(money)`

Formats the amount with the correct number of decimal places for its currency,
followed by a space and the currency code. Zero-exponent currencies have **no
decimal point**. Negative amounts get a leading `-`.

```elixir
Money.to_string(Money.new(12345, :USD))    # => "123.45 USD"
Money.to_string(Money.new(500, :JPY))      # => "500 JPY"
Money.to_string(Money.new(1234567, :BHD))  # => "1234.567 BHD"
Money.to_string(Money.new(-5, :USD))       # => "-0.05 USD"
```

## Constraints

- Single file, module named `Money`.
- Use only the Elixir/OTP standard library — no external dependencies.
- Do not use floats for storage; only `from_major/2` and `multiply/2` may
  involve a float, and their results must be rounded back to integer minor units.