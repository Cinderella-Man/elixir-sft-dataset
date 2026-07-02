# Fill in the middle: `Money.multiply/2`

The module below is a complete, working `Money` implementation **except** for the
`multiply/2` function, whose body has been replaced with `# TODO`. Implement
`multiply/2` so the module behaves as documented.

## What `multiply/2` must do

`Money.multiply(money, factor)` multiplies a `Money` value by a **number**
(integer or float) and returns a **new `Money` struct** with the **same
currency**.

- The new cent amount is the original `amount` multiplied by `factor`, then
  **rounded to the nearest whole cent**, with halves rounded **away from zero**
  (exactly Elixir's built-in `round/1`).
- The result must stay in integer cents — do not store a float in the struct.
- `factor` may be any number: a positive or negative integer, or a float.

```elixir
Money.multiply(Money.new(101, :USD), 0.5)   # => %Money{amount: 51, currency: :USD}
Money.multiply(Money.new(100, :USD), 3)     # => %Money{amount: 300, currency: :USD}
Money.multiply(Money.new(100, :USD), -1.5)  # => %Money{amount: -150, currency: :USD}
```

If `factor` is **not a number**, raise `ArgumentError`.

```elixir
Money.multiply(Money.new(100, :USD), :nope)  # raises ArgumentError
```

## Module

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
    # TODO
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