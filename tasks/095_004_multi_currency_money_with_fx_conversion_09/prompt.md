# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `fetch_rate` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Multi-Currency Money with FX Conversion

Write me an Elixir module called `Money` that handles multi-currency amounts
(stored as **integer cents**) and can **convert between currencies** and sum a
mixed-currency collection using an exchange-rate table. Same-currency
arithmetic stays strict; cross-currency work goes explicitly through conversion.

## The struct

`Money` must be a struct with exactly two fields:

- `:amount` — an integer number of cents (may be negative)
- `:currency` — a currency atom such as `:USD`, `:EUR`, `:GBP`

## Rate tables

Exchange rates are a plain map from a currency atom to a **float rate**: the
value of one unit of that currency expressed in a common base.

```elixir
rates = %{USD: 1.0, EUR: 1.10, GBP: 1.25}
```

To convert an amount from currency `from` to currency `to`, compute
`round(amount * rates[from] / rates[to])`. Converting to the same currency
returns the same amount — but the rate lookup still applies, so a currency
missing from `rates` raises even when the source and target are equal.

## Public API

### `Money.new(cents, currency)`

Creates a money struct. `cents` is an **integer**, `currency` is an **atom**.
Raise `ArgumentError` if `cents` is not an integer or `currency` is not an atom.

### `Money.add(a, b)` / `Money.subtract(a, b)`

Add / subtract two money values. **Both must have the same currency.** Returns a
new `Money` struct. If the currencies differ, raise `ArgumentError` — these
functions never auto-convert.

### `Money.multiply(money, factor)`

Multiplies by a **number** (integer or float), rounding the resulting cents to
the nearest whole cent (round halves away from zero). Same currency.

### `Money.split(money, n)`

Divides evenly among `n` parties (`n` a **positive integer**), distributing the
remainder to the first `rem(amount, n)` parties so shares sum back to the
original. Returns a list of `n` `Money` structs. Raise `ArgumentError` if `n` is
not a positive integer.

### `Money.convert(money, to_currency, rates)`

Converts `money` into `to_currency` using the rate table, rounding the result to
the nearest whole cent. Returns a new `Money` struct in `to_currency`.

```elixir
rates = %{USD: 1.0, EUR: 1.10, GBP: 1.25}

Money.convert(Money.new(100, :USD), :EUR, rates)
# => %Money{amount: 91, currency: :EUR}   (100 * 1.0 / 1.10 = 90.9 -> 91)

Money.convert(Money.new(100, :EUR), :USD, rates)
# => %Money{amount: 110, currency: :USD}  (100 * 1.10 / 1.0 = 110)

Money.convert(Money.new(80, :USD), :USD, rates)
# => %Money{amount: 80, currency: :USD}   (same currency)
```

If either the source or target currency is missing from `rates`, raise
`ArgumentError`. This applies even when the source and target currency are the
same: converting an unknown currency to itself still raises.

### `Money.total(list_of_money, currency, rates)`

Converts every `Money` in the list into `currency` (rounding each conversion
independently) and sums them into a single `Money` struct in `currency`. An
empty list totals to zero in `currency`.

```elixir
Money.total([Money.new(100, :USD), Money.new(100, :EUR)], :USD, rates)
# => %Money{amount: 210, currency: :USD}   (100 USD + 110 USD)
```

## Constraints

- Single file, module named `Money`.
- Use only the Elixir/OTP standard library — no external dependencies.
- Do not use floats for storage; only `multiply/2`, `convert/3`, and `total/3`
  may involve floats, and their results must be rounded back to integer cents.

## The module with `fetch_rate` missing

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
    # TODO
  end
end
```

Give me only the complete implementation of `fetch_rate` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
