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
returns the same amount.

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
`ArgumentError`.

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
