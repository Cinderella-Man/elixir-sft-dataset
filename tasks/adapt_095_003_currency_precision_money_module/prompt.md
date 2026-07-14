# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Money do
  @moduledoc """
  Safe multi-currency arithmetic.

  All amounts are stored internally as integer cents to avoid any
  floating-point representation problems. Each `Money` value carries a
  currency atom (e.g. `:USD`, `:EUR`, `:JPY`) and arithmetic between two
  `Money` values is only permitted when the currencies match.
  """

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: integer(), currency: atom()}

  @doc """
  Creates a money struct from an integer number of `cents` and a currency atom.

  Raises `ArgumentError` if `cents` is not an integer or `currency` is not an atom.

      iex> Money.new(100, :USD)
      %Money{amount: 100, currency: :USD}
  """
  @spec new(integer(), atom()) :: t()
  def new(cents, currency) when is_integer(cents) and is_atom(currency) do
    %__MODULE__{amount: cents, currency: currency}
  end

  def new(_cents, _currency) do
    raise ArgumentError, "cents must be an integer and currency must be an atom"
  end

  @doc """
  Adds two money values of the same currency.

  Raises `ArgumentError` if the currencies differ.
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a + b, currency: cur}
  end

  def add(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError, "cannot add different currencies: #{inspect(c1)} and #{inspect(c2)}"
  end

  @doc """
  Subtracts `b` from `a` when both share the same currency.

  Raises `ArgumentError` if the currencies differ. The result may be negative.
  """
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a - b, currency: cur}
  end

  def subtract(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError, "cannot subtract different currencies: #{inspect(c1)} and #{inspect(c2)}"
  end

  @doc """
  Multiplies a money value by a number (integer or float).

  The resulting cent amount is rounded to the nearest whole cent, with halves
  rounded away from zero (Elixir's `round/1`).
  """
  @spec multiply(t(), number()) :: t()
  def multiply(%__MODULE__{amount: amount, currency: currency}, factor) when is_number(factor) do
    %__MODULE__{amount: round(amount * factor), currency: currency}
  end

  def multiply(%__MODULE__{}, _factor) do
    raise ArgumentError, "factor must be a number"
  end

  @doc """
  Splits a money value evenly among `n` parties (a positive integer).

  Returns a list of `n` `Money` structs. The remainder is distributed one cent
  at a time to the first `rem(amount, n)` parties, so the results always sum
  back to the original amount.

  Raises `ArgumentError` if `n` is not a positive integer.
  """
  @spec split(t(), pos_integer()) :: [t()]
  def split(%__MODULE__{amount: amount, currency: currency}, n)
      when is_integer(n) and n > 0 do
    base = div(amount, n)
    remainder = rem(amount, n)

    Enum.map(0..(n - 1), fn i ->
      cents = if i < remainder, do: base + 1, else: base
      %__MODULE__{amount: cents, currency: currency}
    end)
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end
end
```

## New specification

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
Money.from_major(1.2345, :BHD) # => %Money{amount: 1235, currency: :BHD}
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
distribute the remainder one minor unit at a time to the first
`Integer.mod(amount, n)` parties so the shares always sum back to the original
amount — including negative amounts (floored division, so e.g. `-5` split 2
ways is `[-2, -3]`). Raise `ArgumentError` if `n` is not a positive integer.

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
