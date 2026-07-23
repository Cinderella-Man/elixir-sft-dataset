# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule Money do
  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  def new(cents, currency) when is_integer(cents) and is_atom(currency) do
    %__MODULE__{amount: cents, currency: currency}
  end

  def new(_cents, _currency) do
    raise ArgumentError, "cents must be an integer and currency must be an atom"
  end

  def add(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a + b, currency: cur}
  end

  def add(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError,
          "cannot add different currencies: #{inspect(c1)} and #{inspect(c2)}; use convert/3"
  end

  def subtract(%__MODULE__{amount: a, currency: cur}, %__MODULE__{amount: b, currency: cur}) do
    %__MODULE__{amount: a - b, currency: cur}
  end

  def subtract(%__MODULE__{currency: c1}, %__MODULE__{currency: c2}) do
    raise ArgumentError,
          "cannot subtract different currencies: #{inspect(c1)} and #{inspect(c2)}; use convert/3"
  end

  def multiply(%__MODULE__{amount: amount, currency: currency}, factor) when is_number(factor) do
    %__MODULE__{amount: round(amount * factor), currency: currency}
  end

  def multiply(%__MODULE__{}, _factor) do
    raise ArgumentError, "factor must be a number"
  end

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

  def convert(%__MODULE__{amount: amount, currency: from}, to, rates)
      when is_atom(to) and is_map(rates) do
    rate_from = fetch_rate(rates, from)
    rate_to = fetch_rate(rates, to)
    %__MODULE__{amount: round(amount * rate_from / rate_to), currency: to}
  end

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
