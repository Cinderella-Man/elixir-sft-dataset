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
# => %Money{amount: 100, currency: :USD}
Money.new(100, :USD)
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
# => %Money{amount: 51, currency: :USD}
Money.multiply(Money.new(101, :USD), 0.5)
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

## Module under test

```elixir
defmodule Money do
  @moduledoc """
  Safe multi-currency arithmetic with weighted allocation.

  All amounts are stored internally as integer cents to avoid any
  floating-point representation problems. Each `Money` value carries a
  currency atom (e.g. `:USD`, `:EUR`, `:JPY`) and arithmetic between two
  `Money` values is only permitted when the currencies match. Amounts can be
  divided among parties by arbitrary integer weights via `allocate/2`, with the
  remainder distributed fairly so shares always sum back to the original.
  """

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: integer(), currency: atom()}

  @doc """
  Creates a money struct from an integer number of `cents` and a currency atom.

  Raises `ArgumentError` if `cents` is not an integer or `currency` is not an atom.
  """
  @spec new(integer(), atom()) :: t()
  def new(cents, currency) when is_integer(cents) and is_atom(currency) do
    %__MODULE__{amount: cents, currency: currency}
  end

  def new(_cents, _currency) do
    raise ArgumentError, "cents must be an integer and currency must be an atom"
  end

  @doc "Adds two money values of the same currency."
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a + b, currency: cur}
  end

  def add(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError, "cannot add different currencies: #{inspect(c1)} and #{inspect(c2)}"
  end

  @doc "Subtracts `b` from `a` when both share the same currency."
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
  Divides a money value among parties according to a list of integer weights.

  Each party's base share is `div(amount * ratio, total)`; the leftover
  remainder is distributed one cent at a time to the earliest parties (negative
  cents for negative amounts). Shares always sum back to the original amount.

  Raises `ArgumentError` unless `ratios` is a non-empty list of non-negative
  integers whose sum is strictly positive.
  """
  @spec allocate(t(), [non_neg_integer()]) :: [t()]
  def allocate(%__MODULE__{amount: amount, currency: currency}, ratios)
      when is_list(ratios) and ratios != [] do
    unless Enum.all?(ratios, &(is_integer(&1) and &1 >= 0)) do
      raise ArgumentError, "ratios must be non-negative integers"
    end

    total = Enum.sum(ratios)

    if total <= 0 do
      raise ArgumentError, "ratios must sum to a strictly positive value"
    end

    shares = Enum.map(ratios, fn r -> div(amount * r, total) end)
    remainder = amount - Enum.sum(shares)
    unit = if remainder >= 0, do: 1, else: -1
    count = abs(remainder)

    shares
    |> Enum.with_index()
    |> Enum.map(fn {share, i} ->
      cents = if i < count, do: share + unit, else: share
      %__MODULE__{amount: cents, currency: currency}
    end)
  end

  def allocate(%__MODULE__{}, _ratios) do
    raise ArgumentError, "ratios must be a non-empty list of non-negative integers"
  end

  @doc """
  Splits a money value evenly among `n` parties (a positive integer).

  Equivalent to `allocate/2` with `n` equal weights.
  """
  @spec split(t(), pos_integer()) :: [t()]
  def split(%__MODULE__{} = money, n) when is_integer(n) and n > 0 do
    allocate(money, List.duplicate(1, n))
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end
end
```
