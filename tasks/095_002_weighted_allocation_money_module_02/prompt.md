# Weighted Allocation — Implement `allocate/2`

You are given the `Money` module below, fully implemented except for the
`allocate/2` function. Implement `allocate/2` so that it divides a money value
among parties according to a list of **integer weights**.

`allocate/2` receives a `%Money{}` struct and `ratios`, a **non-empty list of
non-negative integers** whose sum is **strictly positive**. It returns a **list
of `Money` structs**, one per weight, each keeping the original currency.

Requirements:

- Validate the input. `ratios` must be a non-empty list, every element must be a
  non-negative integer, and the sum of the weights must be strictly positive. If
  any of these conditions fails, raise `ArgumentError`.
- Let `total` be the sum of the weights. Each party's **base share** is
  `div(amount * ratio, total)` (truncating integer division).
- Because integer cents may not divide cleanly, compute the leftover
  **remainder** as `amount - sum(base_shares)`. Distribute it **one cent at a
  time to the earliest parties**, in list order. When `amount` is negative the
  remainder is negative, so distribute **one negative cent** at a time instead.
- This guarantees the returned amounts always **sum back to the original
  amount**. Every returned struct keeps the original currency.

```elixir
Money.allocate(Money.new(100, :USD), [3, 7])
# => [%Money{amount: 30, currency: :USD}, %Money{amount: 70, currency: :USD}]

Money.allocate(Money.new(10, :USD), [1, 1, 1, 1])
# => [%Money{amount: 3, ...}, %Money{amount: 3, ...},
#     %Money{amount: 2, ...}, %Money{amount: 2, ...}]   (remainder 2 -> first two parties)

Money.allocate(Money.new(1000, :USD), [1, 1, 1])
# => [%Money{amount: 334, ...}, %Money{amount: 333, ...}, %Money{amount: 333, ...}]
```

Implement only the body of `allocate/2` (marked with `# TODO`). Leave every other
function in the module unchanged.

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
  def allocate(%__MODULE__{amount: amount, currency: currency}, ratios) do
    # TODO
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