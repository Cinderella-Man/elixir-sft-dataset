# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
    case Map.fetch(rates, currency) do
      {:ok, rate} when is_number(rate) -> rate
      _ -> raise ArgumentError, "no rate for currency #{inspect(currency)}"
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MoneyTest do
  use ExUnit.Case, async: false

  @rates %{USD: 1.0, EUR: 1.10, GBP: 1.25}

  # -------------------------------------------------------
  # new/2
  # -------------------------------------------------------

  test "new/2 builds a struct" do
    m = Money.new(100, :USD)
    assert m.amount == 100
    assert m.currency == :USD
  end

  test "new/2 allows negatives and zero" do
    assert Money.new(-250, :EUR).amount == -250
    assert Money.new(0, :GBP).amount == 0
  end

  test "new/2 raises on bad types" do
    assert_raise ArgumentError, fn -> Money.new(1.5, :USD) end
    assert_raise ArgumentError, fn -> Money.new(100, "USD") end
  end

  # -------------------------------------------------------
  # add/2 & subtract/2 (strict, no auto-convert)
  # -------------------------------------------------------

  test "add/2 and subtract/2 work on same currency" do
    assert Money.add(Money.new(100, :USD), Money.new(250, :USD)).amount == 350
    assert Money.subtract(Money.new(200, :USD), Money.new(500, :USD)).amount == -300
  end

  test "add/2 and subtract/2 refuse cross-currency operands" do
    assert_raise ArgumentError, fn -> Money.add(Money.new(1, :USD), Money.new(1, :EUR)) end
    assert_raise ArgumentError, fn -> Money.subtract(Money.new(1, :USD), Money.new(1, :GBP)) end
  end

  # -------------------------------------------------------
  # multiply/2
  # -------------------------------------------------------

  test "multiply/2 rounds halves away from zero" do
    assert Money.multiply(Money.new(101, :USD), 0.5).amount == 51
    assert Money.multiply(Money.new(100, :USD), 3).amount == 300
  end

  # -------------------------------------------------------
  # split/2
  # -------------------------------------------------------

  test "split/2 distributes remainder and sums back" do
    parts = Money.split(Money.new(1000, :USD), 3)
    amounts = Enum.map(parts, & &1.amount)
    assert amounts == [334, 333, 333]
    assert Enum.sum(amounts) == 1000
  end

  test "split/2 raises when n is not a positive integer" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 0) end
  end

  # -------------------------------------------------------
  # convert/3
  # -------------------------------------------------------

  test "convert/3 USD to EUR rounds correctly" do
    result = Money.convert(Money.new(100, :USD), :EUR, @rates)
    assert result.amount == 91
    assert result.currency == :EUR
  end

  test "convert/3 EUR to USD" do
    assert Money.convert(Money.new(100, :EUR), :USD, @rates).amount == 110
  end

  test "convert/3 USD to GBP" do
    assert Money.convert(Money.new(100, :USD), :GBP, @rates).amount == 80
  end

  test "convert/3 to the same currency is a no-op amount" do
    result = Money.convert(Money.new(80, :USD), :USD, @rates)
    assert result.amount == 80
    assert result.currency == :USD
  end

  test "convert/3 handles negative amounts" do
    assert Money.convert(Money.new(-100, :EUR), :USD, @rates).amount == -110
  end

  test "convert/3 raises when a currency is missing from the rate table" do
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :JPY), :USD, @rates) end
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :USD), :JPY, @rates) end
  end

  test "convert round-trip is approximately identity within rounding" do
    eur = Money.convert(Money.new(100, :USD), :EUR, @rates)
    back = Money.convert(eur, :USD, @rates)
    # 100 -> 91 EUR -> 100 USD (91 * 1.10 / 1.0 = 100.1 -> 100)
    assert back.amount == 100
  end

  # -------------------------------------------------------
  # total/3
  # -------------------------------------------------------

  test "total/3 converts each and sums into the target currency" do
    result = Money.total([Money.new(100, :USD), Money.new(100, :EUR)], :USD, @rates)
    assert result.amount == 210
    assert result.currency == :USD
  end

  test "total/3 of an empty list is zero in the target currency" do
    result = Money.total([], :EUR, @rates)
    assert result.amount == 0
    assert result.currency == :EUR
  end

  test "total/3 rounds each conversion independently" do
    # Two 100 USD -> EUR each round to 91, total 182 (not round(200*1.0/1.10)=182 here, same)
    result = Money.total([Money.new(100, :USD), Money.new(100, :USD)], :EUR, @rates)
    assert result.amount == 182
  end

  test "total/3 sums per-element conversions rather than converting the summed amount" do
    # Each 5 USD rounds to 5 EUR (5 * 1.0 / 1.10 = 4.55 -> 5), so the total is 10.
    # Summing first and converting once would give 9 (10 * 1.0 / 1.10 = 9.09 -> 9).
    eur = Money.total([Money.new(5, :USD), Money.new(5, :USD)], :EUR, @rates)
    assert eur.amount == 10
    assert eur.currency == :EUR

    # Each 3 USD rounds to 2 GBP (3 * 1.0 / 1.25 = 2.4 -> 2), so the total is 6.
    # Summing first and converting once would give 7 (9 * 1.0 / 1.25 = 7.2 -> 7).
    gbp = Money.total([Money.new(3, :USD), Money.new(3, :USD), Money.new(3, :USD)], :GBP, @rates)
    assert gbp.amount == 6
    assert gbp.currency == :GBP
  end

  test "total/3 with a single already-target-currency element" do
    result = Money.total([Money.new(55, :GBP)], :GBP, @rates)
    assert result.amount == 55
  end

  test "total/3 raises when any element uses an unknown currency" do
    assert_raise ArgumentError, fn ->
      Money.total([Money.new(1, :USD), Money.new(1, :JPY)], :USD, @rates)
    end
  end

  # -------------------------------------------------------
  # Integration
  # -------------------------------------------------------

  test "mixed-currency cart totals correctly and splits back" do
    cart = [
      Money.new(1000, :USD),
      Money.new(500, :EUR),
      Money.new(400, :GBP)
    ]

    total = Money.total(cart, :USD, @rates)
    # 1000 + round(500*1.10) + round(400*1.25) = 1000 + 550 + 500 = 2050
    assert total.amount == 2050
    assert total.currency == :USD

    parts = Money.split(total, 4)
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 2050
  end

  test "split/2 shares sum back to the original for a negative amount" do
    parts = Money.split(Money.new(-1000, :USD), 3)
    amounts = Enum.map(parts, & &1.amount)
    assert length(amounts) == 3
    assert Enum.all?(parts, &(&1.currency == :USD))
    assert Enum.sum(amounts) == -1000
  end

  test "multiply/2 rounds negative halves away from zero" do
    assert Money.multiply(Money.new(-101, :USD), 0.5).amount == -51
    assert Money.multiply(Money.new(-1, :USD), 0.5).amount == -1
    assert Money.multiply(Money.new(1, :USD), 0.5).amount == 1
  end

  test "split/2 raises for a float n and for a negative n" do
    # TODO
  end

  test "new/2 returns a struct carrying exactly the amount and currency fields" do
    m = Money.new(7, :GBP)
    # Map key iteration order is an implementation detail; compare as a set.
    assert Enum.sort(Map.keys(Map.from_struct(m))) == [:amount, :currency]
    assert m.__struct__ == Money
  end

  test "convert/3 raises for an unknown currency even when source and target match" do
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :JPY), :JPY, @rates) end
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :CHF), :JPY, @rates) end
  end

  test "multiply convert and total always store integer cents" do
    assert is_integer(Money.multiply(Money.new(101, :USD), 1.5).amount)
    assert is_integer(Money.convert(Money.new(37, :EUR), :GBP, @rates).amount)
    mixed = [Money.new(100, :USD), Money.new(33, :EUR), Money.new(7, :GBP)]
    assert is_integer(Money.total(mixed, :GBP, @rates).amount)
    assert is_integer(Money.total([], :EUR, @rates).amount)
  end
end
```
