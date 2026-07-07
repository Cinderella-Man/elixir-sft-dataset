# Fill in the middle: `Money.split/2`

Implement the public `split/2` function for the `Money` module.

`split(money, n)` divides a `Money` value evenly among `n` parties, where `n`
must be a **positive integer**, working entirely in **whole minor units** (never
floats). It returns a **list of `n` `Money` structs**, all in the same currency
as the input.

Compute the base share as the integer quotient `div(amount, n)` and the leftover
as `rem(amount, n)`. Because integer division drops the remainder, distribute
that remainder one minor unit at a time to the **first `rem(amount, n)` parties**
(each of them gets `base + 1`; the rest get `base`). This guarantees the shares
always sum back to the original `amount`, even for negative amounts. For example,
`split(Money.new(1000, :JPY), 3)` yields shares `[334, 333, 333]`.

If `n` is not a positive integer, raise `ArgumentError`.

```elixir
defmodule Money do
  @moduledoc """
  Safe multi-currency arithmetic with per-currency precision.

  Amounts are stored as integer minor units. Each supported currency has an
  exponent (number of decimal places): USD/EUR/GBP = 2, JPY = 0, KWD/BHD = 3.
  Formatting and major<->minor conversion respect the currency's exponent.
  """

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: integer(), currency: atom()}

  @exponents %{USD: 2, EUR: 2, GBP: 2, JPY: 0, KWD: 3, BHD: 3}

  @doc "Returns the minor-unit exponent for a supported currency."
  @spec exponent(atom()) :: non_neg_integer()
  def exponent(currency) do
    case Map.fetch(@exponents, currency) do
      {:ok, exp} -> exp
      :error -> raise ArgumentError, "unsupported currency: #{inspect(currency)}"
    end
  end

  @doc """
  Creates a money struct from an integer number of minor units.

  Raises `ArgumentError` if `minor_units` is not an integer or `currency` is
  not supported.
  """
  @spec new(integer(), atom()) :: t()
  def new(minor_units, currency) when is_integer(minor_units) and is_atom(currency) do
    _ = exponent(currency)
    %__MODULE__{amount: minor_units, currency: currency}
  end

  def new(_minor_units, _currency) do
    raise ArgumentError, "minor_units must be an integer and currency must be a supported atom"
  end

  @doc """
  Creates a money struct from a major amount by scaling to minor units and
  rounding to the nearest whole minor unit.
  """
  @spec from_major(number(), atom()) :: t()
  def from_major(major, currency) when is_number(major) and is_atom(currency) do
    exp = exponent(currency)
    %__MODULE__{amount: round(major * Integer.pow(10, exp)), currency: currency}
  end

  def from_major(_major, _currency) do
    raise ArgumentError, "major must be a number and currency must be a supported atom"
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

  @doc "Multiplies a money value by a number, rounding to a whole minor unit."
  @spec multiply(t(), number()) :: t()
  def multiply(%__MODULE__{amount: amount, currency: currency}, factor) when is_number(factor) do
    %__MODULE__{amount: round(amount * factor), currency: currency}
  end

  def multiply(%__MODULE__{}, _factor) do
    raise ArgumentError, "factor must be a number"
  end

  def split(%__MODULE__{amount: amount, currency: currency}, n)
      when is_integer(n) and n > 0 do
    # TODO
  end

  @doc "Formats the amount with currency-appropriate decimals and code."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{amount: amount, currency: currency}) do
    exp = exponent(currency)
    sign = if amount < 0, do: "-", else: ""
    abs_amount = abs(amount)

    if exp == 0 do
      "#{sign}#{abs_amount} #{currency}"
    else
      divisor = Integer.pow(10, exp)
      major = div(abs_amount, divisor)
      minor = rem(abs_amount, divisor)
      minor_str = minor |> Integer.to_string() |> String.pad_leading(exp, "0")
      "#{sign}#{major}.#{minor_str} #{currency}"
    end
  end
end
```