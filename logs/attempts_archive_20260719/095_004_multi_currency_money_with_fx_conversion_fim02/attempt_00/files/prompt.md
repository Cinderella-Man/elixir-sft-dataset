# Implement `Money.convert/3`

Implement the public `convert/3` function. It takes a `Money` struct, a target
currency atom `to`, and a `rates` map, and returns a new `Money` struct holding
the same value expressed in `to`.

Guard the clause so it only matches when `to` is an atom and `rates` is a map.
Look up the source currency's rate and the target currency's rate by calling the
private helper `fetch_rate/2` (which raises `ArgumentError` when a currency is
missing from the table or its rate is not a number). Compute the converted
amount as `round(amount * rate_from / rate_to)` — the source amount scaled by
the source rate and divided by the target rate, rounded to the nearest whole
cent. Return a `%Money{}` struct carrying that amount with its currency set to
`to`. Converting to the same currency naturally yields the same amount because
`rate_from` and `rate_to` are equal.

```elixir
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
  distributing the remainder to the first `rem(amount, n)` parties.
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

  @doc """
  Converts `money` into `to_currency` using the rate table, rounding to a whole
  cent. Raises `ArgumentError` if either currency is missing from `rates`.
  """
  @spec convert(t(), atom(), rates()) :: t()
  def convert(%__MODULE__{amount: amount, currency: from}, to, rates)
      when is_atom(to) and is_map(rates) do
    # TODO
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
```