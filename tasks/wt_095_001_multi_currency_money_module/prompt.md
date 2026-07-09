# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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
# => %Money{amount: 100, currency: :USD}   (== $1.00)
Money.new(100, :USD)
# => %Money{amount: 1000, currency: :USD}  (== $10.00)
Money.new(1000, :USD)
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
the same currency.

```elixir
# => %Money{amount: 300, currency: :USD}
Money.multiply(Money.new(100, :USD), 3)
# => %Money{amount: 10,  currency: :USD}
Money.multiply(Money.new(100, :USD), 0.1)
# => %Money{amount: 51,  currency: :USD}  (50.5 -> 51)
Money.multiply(Money.new(101, :USD), 0.5)
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
```

Every returned struct keeps the original currency. If `n` is not a positive
integer, raise `ArgumentError`.

## Constraints

- Single file, module named `Money`.
- Use only the Elixir/OTP standard library — no external dependencies.
- Do not use floats for storage; only `multiply/2` may involve a float factor,
  and its result must be rounded back to an integer cent count.

## Module under test

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
