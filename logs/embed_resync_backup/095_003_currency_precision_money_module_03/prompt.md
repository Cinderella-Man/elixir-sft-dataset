Implement the public `to_string/1` function. It takes a `Money` struct and returns a
`String.t()` formatting the amount with the correct number of decimal places for its
currency, followed by a single space and the currency code.

Look up the currency's exponent with `exponent/1`. Determine the sign: a negative
amount gets a leading `"-"`, otherwise no sign prefix; format the absolute value of the
amount. If the exponent is `0` (e.g. `:JPY`), there is no decimal point at all — just
the integer amount, a space, and the currency. Otherwise, split the absolute amount
into a major part (`div` by `10^exp`) and a minor part (`rem` by `10^exp`), zero-pad the
minor part on the left to `exp` digits, and join them with a `"."`, followed by a space
and the currency.

```elixir
# => "123.45 USD"
Money.to_string(Money.new(12345, :USD))
# => "500 JPY"
Money.to_string(Money.new(500, :JPY))
# => "1234.567 BHD"
Money.to_string(Money.new(1_234_567, :BHD))
# => "-0.05 USD"
Money.to_string(Money.new(-5, :USD))
```

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

  @doc """
  Splits a money value evenly among `n` parties (a positive integer), working
  in whole minor units. The remainder is given to the first `rem(amount, n)`
  parties so shares sum back to the original.
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

  @doc "Formats the amount with currency-appropriate decimals and code."
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{amount: amount, currency: currency}) do
    # TODO
  end
end
```