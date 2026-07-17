defmodule Money do
  @moduledoc """
  Multi-currency amounts stored as integer cents, with explicit FX conversion.

  Same-currency arithmetic (`add/2`, `subtract/2`) is strict and never
  auto-converts. Cross-currency work goes through `convert/3` and `total/3`,
  which use a rate table mapping each currency atom to its value (a float) in a
  common base: `round(amount * rates[from] / rates[to])`.
  """

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: integer(), currency: atom()}
  @type rates :: %{optional(atom()) => number()}

  @doc "Creates a money struct from integer `cents` and a currency atom."
  @spec new(integer(), atom()) :: t()
  def new(cents, currency) when is_integer(cents) and is_atom(currency) do
    %__MODULE__{amount: cents, currency: currency}
  end

  def new(_cents, _currency) do
    raise ArgumentError, "cents must be an integer and currency must be an atom"
  end

  @doc "Adds two money values of the same currency (never auto-converts)."
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a + b, currency: cur}
  end

  def add(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError,
          "cannot add different currencies: #{inspect(c1)} and #{inspect(c2)}; use convert/3"
  end

  @doc "Subtracts `b` from `a` when both share the same currency."
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a - b, currency: cur}
  end

  def subtract(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError,
          "cannot subtract different currencies: #{inspect(c1)} and #{inspect(c2)}; use convert/3"
  end

  @doc "Multiplies a money value by a number, rounding to a whole cent."
  @spec multiply(t(), number()) :: t()
  def multiply(%__MODULE__{amount: amount, currency: currency}, factor) when is_number(factor) do
    %__MODULE__{amount: round(amount * factor), currency: currency}
  end

  def multiply(%__MODULE__{}, _factor) do
    raise ArgumentError, "factor must be a number"
  end

  @doc """
  Splits a money value evenly among `n` parties (a positive integer),
  distributing the remainder to the first `rem(amount, n)` parties so the
  shares always sum back to the original amount, including negative amounts.
  """
  @spec split(t(), pos_integer()) :: [t()]
  def split(%__MODULE__{amount: amount, currency: currency}, n)
      when is_integer(n) and n > 0 do
    base = div(amount, n)
    remainder = rem(amount, n)
    step = if remainder < 0, do: -1, else: 1
    extras = abs(remainder)

    Enum.map(0..(n - 1), fn i ->
      cents = if i < extras, do: base + step, else: base
      %__MODULE__{amount: cents, currency: currency}
    end)
  end

  def split(%__MODULE__{}, _n) do
    raise ArgumentError, "n must be a positive integer"
  end

  @doc """
  Converts `money` into `to_currency` using the rate table, rounding to a whole
  cent. Raises `ArgumentError` if either currency is missing from `rates`.
  """
  @spec convert(t(), atom(), rates()) :: t()
  def convert(%__MODULE__{amount: amount, currency: from}, to, rates)
      when is_atom(to) and is_map(rates) do
    rate_from = fetch_rate(rates, from)
    rate_to = fetch_rate(rates, to)
    %__MODULE__{amount: round(amount * rate_from / rate_to), currency: to}
  end

  @doc """
  Converts every money in `list` into `currency` (rounding each independently)
  and sums them into one money struct. An empty list totals to zero.
  """
  @spec total([t()], atom(), rates()) :: t()
  def total(list, currency, rates)
      when is_list(list) and is_atom(currency) and is_map(rates) do
    sum =
      Enum.reduce(list, 0, fn %__MODULE__{} = m, acc ->
        acc + convert(m, currency, rates).amount
      end)

    %__MODULE__{amount: sum, currency: currency}
  end

  defp fetch_rate(rates, currency) do
    case Map.fetch(rates, currency) do
      {:ok, rate} when is_number(rate) -> rate
      _ -> raise ArgumentError, "no rate for currency #{inspect(currency)}"
    end
  end
end
