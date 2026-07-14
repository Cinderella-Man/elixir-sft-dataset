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
