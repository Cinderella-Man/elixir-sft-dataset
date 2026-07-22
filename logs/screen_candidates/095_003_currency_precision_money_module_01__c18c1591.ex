defmodule Money do
  @moduledoc """
  Multi-currency money with per-currency minor-unit precision.

  Amounts are stored as **integer minor units** (cents for `:USD`, whole yen for `:JPY`,
  thousandths of a dinar for `:BHD`, ...), so no value is ever kept as a float and no
  floating-point representation error can accumulate across arithmetic.

  Each supported currency has a *minor-unit exponent* — the number of decimal places used
  when the amount is rendered in its major unit:

  | currency | exponent | example                        |
  |----------|----------|--------------------------------|
  | `:USD`   | 2        | `12345` minor units = `123.45` |
  | `:EUR`   | 2        | `12345` = `123.45`             |
  | `:GBP`   | 2        | `12345` = `123.45`             |
  | `:JPY`   | 0        | `500` = `500`                  |
  | `:KWD`   | 3        | `1234567` = `1234.567`         |
  | `:BHD`   | 3        | `1234567` = `1234.567`         |

  Floats appear only as *inputs* to `from_major/2` and `multiply/2`; both round the scaled
  result back to a whole number of minor units (halves away from zero).

      iex> Money.add(Money.new(12345, :USD), Money.from_major(0.55, :USD)) |> Money.to_string()
      "124.00 USD"
  """

  @currencies %{USD: 2, EUR: 2, GBP: 2, JPY: 0, KWD: 3, BHD: 3}

  @typedoc "A supported ISO-4217 currency code."
  @type currency :: :USD | :EUR | :GBP | :JPY | :KWD | :BHD

  @typedoc "A money value: an integer count of minor units tagged with its currency."
  @type t :: %__MODULE__{amount: integer(), currency: currency()}

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @doc """
  Builds a `Money` from an integer number of minor units and a supported currency.

  Raises `ArgumentError` if `minor_units` is not an integer or `currency` is not supported.

      iex> Money.new(12345, :USD)
      %Money{amount: 12345, currency: :USD}

      iex> Money.new(500, :JPY)
      %Money{amount: 500, currency: :JPY}
  """
  @spec new(integer(), currency()) :: t()
  def new(minor_units, currency) when is_integer(minor_units) do
    %__MODULE__{amount: minor_units, currency: validate_currency!(currency)}
  end

  def new(minor_units, _currency) do
    raise ArgumentError,
          "minor units must be an integer, got: #{inspect(minor_units)}"
  end

  @doc """
  Builds a `Money` from a *major* amount (dollars, euros, yen, dinars, ...).

  The major amount is scaled by the currency's exponent and rounded to the nearest whole
  minor unit, with halves rounded away from zero. Raises `ArgumentError` for a non-number
  `major` or an unsupported currency.

      iex> Money.from_major(12.34, :USD)
      %Money{amount: 1234, currency: :USD}

      iex> Money.from_major(500, :JPY)
      %Money{amount: 500, currency: :JPY}

      iex> Money.from_major(1.2345, :BHD)
      %Money{amount: 1235, currency: :BHD}
  """
  @spec from_major(number(), currency()) :: t()
  def from_major(major, currency) when is_number(major) do
    currency = validate_currency!(currency)
    scale = pow10(Map.fetch!(@currencies, currency))
    %__MODULE__{amount: scale_to_minor(major, scale), currency: currency}
  end

  def from_major(major, _currency) do
    raise ArgumentError, "major amount must be a number, got: #{inspect(major)}"
  end

  @doc """
  Adds two money values of the same currency.

  Raises `ArgumentError` if the currencies differ.

      iex> Money.add(Money.new(12345, :USD), Money.new(55, :USD))
      %Money{amount: 12400, currency: :USD}
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{currency: currency} = a, %__MODULE__{currency: currency} = b) do
    %__MODULE__{amount: a.amount + b.amount, currency: currency}
  end

  def add(%__MODULE__{} = a, %__MODULE__{} = b), do: raise_mismatch!(a, b)

  @doc """
  Subtracts `b` from `a`; both must share a currency.

  Raises `ArgumentError` if the currencies differ.

      iex> Money.subtract(Money.new(12345, :USD), Money.new(12350, :USD))
      %Money{amount: -5, currency: :USD}
  """
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{currency: currency} = a, %__MODULE__{currency: currency} = b) do
    %__MODULE__{amount: a.amount - b.amount, currency: currency}
  end

  def subtract(%__MODULE__{} = a, %__MODULE__{} = b), do: raise_mismatch!(a, b)

  @doc """
  Multiplies a money value by a number, keeping the currency.

  The scaled amount is rounded to the nearest whole minor unit (halves away from zero).
  Raises `ArgumentError` if `factor` is not a number.

      iex> Money.multiply(Money.new(1000, :USD), 3)
      %Money{amount: 3000, currency: :USD}

      iex> Money.multiply(Money.new(1000, :USD), 0.075)
      %Money{amount: 75, currency: :USD}
  """
  @spec multiply(t(), number()) :: t()
  def multiply(%__MODULE__{} = money, factor) when is_integer(factor) do
    %__MODULE__{money | amount: money.amount * factor}
  end

  def multiply(%__MODULE__{} = money, factor) when is_float(factor) do
    %__MODULE__{money | amount: round_half_away(money.amount * factor)}
  end

  def multiply(%__MODULE__{}, factor) do
    raise ArgumentError, "factor must be a number, got: #{inspect(factor)}"
  end

  @doc """
  Splits a money value evenly among `n` parties, in whole minor units.

  Returns a list of `n` `Money` structs whose amounts always sum back to the original
  amount. Division is floored, and the remainder (`Integer.mod(amount, n)`, always
  non-negative) is handed out one minor unit at a time to the first parties — so negative
  amounts split correctly too. Raises `ArgumentError` unless `n` is a positive integer.

      iex> Money.split(Money.new(1000, :JPY), 3) |> Enum.map(& &1.amount)
      [334, 333, 333]

      iex> Money.split(Money.new(-5, :USD), 2) |> Enum.map(& &1.amount)
      [-2, -3]
  """
  @spec split(t(), pos_integer()) :: [t()]
  def split(%__MODULE__{} = money, n) when is_integer(n) and n > 0 do
    base = Integer.floor_div(money.amount, n)
    remainder = Integer.mod(money.amount, n)

    Enum.map(0..(n - 1), fn index ->
      extra = if index < remainder, do: 1, else: 0
      %__MODULE__{money | amount: base + extra}
    end)
  end

  def split(%__MODULE__{}, n) do
    raise ArgumentError, "the number of parties must be a positive integer, got: #{inspect(n)}"
  end

  @doc """
  Returns the minor-unit exponent of a supported currency.

  Raises `ArgumentError` for an unsupported currency.

      iex> {Money.exponent(:USD), Money.exponent(:JPY), Money.exponent(:KWD)}
      {2, 0, 3}
  """
  @spec exponent(currency()) :: non_neg_integer()
  def exponent(currency), do: Map.fetch!(@currencies, validate_currency!(currency))

  @doc """
  Formats a money value with its currency's number of decimal places and its code.

  Zero-exponent currencies render without a decimal point; negative amounts keep a leading
  minus sign.

      iex> Money.to_string(Money.new(12345, :USD))
      "123.45 USD"

      iex> Money.to_string(Money.new(500, :JPY))
      "500 JPY"

      iex> Money.to_string(Money.new(1234567, :BHD))
      "1234.567 BHD"

      iex> Money.to_string(Money.new(-5, :USD))
      "-0.05 USD"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{amount: amount, currency: currency}) do
    code = Atom.to_string(currency)
    exp = Map.fetch!(@currencies, currency)
    sign = if amount < 0, do: "-", else: ""
    digits = amount |> abs() |> Integer.to_string() |> String.pad_leading(exp + 1, "0")

    case exp do
      0 ->
        "#{sign}#{digits} #{code}"

      _ ->
        {whole, fraction} = String.split_at(digits, String.length(digits) - exp)
        "#{sign}#{whole}.#{fraction} #{code}"
    end
  end

  # -- internals ----------------------------------------------------------------------

  @spec validate_currency!(term()) :: currency()
  defp validate_currency!(currency) when is_atom(currency) do
    if Map.has_key?(@currencies, currency) do
      currency
    else
      raise ArgumentError, "unsupported currency: #{inspect(currency)}"
    end
  end

  defp validate_currency!(currency) do
    raise ArgumentError, "unsupported currency: #{inspect(currency)}"
  end

  @spec scale_to_minor(number(), pos_integer()) :: integer()
  defp scale_to_minor(major, scale) when is_integer(major), do: major * scale
  defp scale_to_minor(major, scale) when is_float(major), do: round_half_away(major * scale)

  # `round/1` on a float already rounds halves away from zero; this wrapper keeps that
  # intent explicit and accepts already-integral values unchanged.
  @spec round_half_away(number()) :: integer()
  defp round_half_away(value) when is_integer(value), do: value
  defp round_half_away(value) when is_float(value), do: round(value)

  @spec pow10(non_neg_integer()) :: pos_integer()
  defp pow10(exp), do: Integer.pow(10, exp)

  @spec raise_mismatch!(t(), t()) :: no_return()
  defp raise_mismatch!(%__MODULE__{} = a, %__MODULE__{} = b) do
    raise ArgumentError,
          "currency mismatch: #{inspect(a.currency)} and #{inspect(b.currency)}"
  end
end