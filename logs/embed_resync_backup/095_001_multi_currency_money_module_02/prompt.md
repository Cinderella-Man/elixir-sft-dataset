# Multi-Currency Money Module — Fill in `split/2`

Below is a complete `Money` module with one function left unimplemented:
`Money.split/2`. Implement the body of the main `split/2` clause (the one guarded
by `is_integer(n) and n > 0`).

`Money.split(money, n)` divides a money value evenly among `n` parties, where `n`
is a **positive integer**. It must:

- Return a **list of exactly `n` `Money` structs**, each keeping the original
  `currency`.
- Compute the base share as integer-cent division of the amount by `n`
  (`div(amount, n)`).
- Distribute the leftover cents fairly: the first `rem(amount, n)` parties each
  receive **one extra cent**, and the remaining parties receive the base share.
- Guarantee the returned amounts always **sum back to the original amount**
  (this holds for negative amounts too, since `div/2` and `rem/2` truncate toward
  zero consistently).

Examples:

```elixir
Money.split(Money.new(1000, :USD), 3)
# => [%Money{amount: 334, currency: :USD},
#     %Money{amount: 333, currency: :USD},
#     %Money{amount: 333, currency: :USD}]

Money.split(Money.new(900, :USD), 3)
# => [%Money{amount: 300, currency: :USD},
#     %Money{amount: 300, currency: :USD},
#     %Money{amount: 300, currency: :USD}]
```

The `ArgumentError` fallback clause (for when `n` is not a positive integer) is
already provided; you only need to implement the main clause's body.

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
    # TODO
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end
end
```