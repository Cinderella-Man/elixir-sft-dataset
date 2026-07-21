# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
  in whole minor units. The remainder is given to the first
  `Integer.mod(amount, n)` parties so shares sum back to the original — for
  negative amounts too, which is why the division must floor rather than
  truncate toward zero.
  """
  @spec split(t(), pos_integer()) :: [t()]
  def split(%__MODULE__{amount: amount, currency: currency}, n)
      when is_integer(n) and n > 0 do
    base = Integer.floor_div(amount, n)
    remainder = Integer.mod(amount, n)

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

## Test harness — implement the `# TODO` test

```elixir
defmodule MoneyTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # exponent/1
  # -------------------------------------------------------

  test "exponent/1 returns the right precision per currency" do
    assert Money.exponent(:USD) == 2
    assert Money.exponent(:JPY) == 0
    assert Money.exponent(:BHD) == 3
    assert Money.exponent(:KWD) == 3
  end

  test "exponent/1 raises on unsupported currency" do
    assert_raise ArgumentError, fn -> Money.exponent(:XYZ) end
  end

  # -------------------------------------------------------
  # new/2
  # -------------------------------------------------------

  test "new/2 builds a struct from minor units" do
    m = Money.new(12345, :USD)
    assert m.amount == 12345
    assert m.currency == :USD
  end

  test "new/2 allows negatives and zero" do
    assert Money.new(-5, :USD).amount == -5
    assert Money.new(0, :JPY).amount == 0
  end

  test "new/2 raises on non-integer amount" do
    assert_raise ArgumentError, fn -> Money.new(1.5, :USD) end
  end

  test "new/2 raises on unsupported currency" do
    assert_raise ArgumentError, fn -> Money.new(100, :XYZ) end
  end

  # -------------------------------------------------------
  # from_major/2
  # -------------------------------------------------------

  test "from_major/2 scales by the currency exponent" do
    assert Money.from_major(12.34, :USD).amount == 1234
    assert Money.from_major(500, :JPY).amount == 500
    assert Money.from_major(1.2345, :BHD).amount == 1235
  end

  test "from_major/2 rounds halves away from zero" do
    # 0.005 USD -> 0.5 cents -> 1
    assert Money.from_major(0.005, :USD).amount == 1
  end

  test "from_major/2 preserves currency and raises on bad input" do
    assert Money.from_major(1, :EUR).currency == :EUR
    assert_raise ArgumentError, fn -> Money.from_major("12", :USD) end
    assert_raise ArgumentError, fn -> Money.from_major(12, :XYZ) end
  end

  # -------------------------------------------------------
  # add/2 & subtract/2
  # -------------------------------------------------------

  test "add/2 and subtract/2 work on same currency" do
    assert Money.add(Money.new(100, :USD), Money.new(250, :USD)).amount == 350
    assert Money.subtract(Money.new(500, :USD), Money.new(200, :USD)).amount == 300
  end

  test "add/2 and subtract/2 raise on currency mismatch" do
    assert_raise ArgumentError, fn -> Money.add(Money.new(1, :USD), Money.new(1, :EUR)) end
    assert_raise ArgumentError, fn -> Money.subtract(Money.new(1, :USD), Money.new(1, :JPY)) end
  end

  # -------------------------------------------------------
  # multiply/2
  # -------------------------------------------------------

  test "multiply/2 rounds to whole minor units" do
    assert Money.multiply(Money.new(101, :USD), 0.5).amount == 51
    assert Money.multiply(Money.new(100, :JPY), 3).amount == 300
  end

  # -------------------------------------------------------
  # split/2
  # -------------------------------------------------------

  test "split/2 distributes remainder and sums back" do
    parts = Money.split(Money.new(1000, :JPY), 3)
    amounts = Enum.map(parts, & &1.amount)
    assert amounts == [334, 333, 333]
    assert Enum.sum(amounts) == 1000
  end

  test "split/2 works for a 3-decimal currency" do
    parts = Money.split(Money.new(1000, :BHD), 3)
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 1000
  end

  test "split/2 raises when n is not a positive integer" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 0) end
  end

  test "split/2 always sums back to the original amount" do
    for amount <- [0, 1, 7, 100, 101, 999, 12_345], n <- 1..9 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount
    end
  end

  test "split/2 sums back over the same grid mirrored into negative amounts" do
    # The sum-back guarantee is unconditional: every amount in the positive
    # grid, negated, must still be reconstructed exactly by its n shares, and
    # each split must yield exactly n shares in the original currency.
    for amount <- [0, -1, -7, -100, -101, -999, -12_345], n <- 1..9 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert length(parts) == n
      assert Enum.all?(parts, &(&1.currency == :USD))
      assert Enum.all?(parts, &is_integer(&1.amount))
      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount
    end
  end

  test "split/2 floors for negative amounts so shares still sum back" do
    parts = Money.split(Money.new(-5, :USD), 2)
    assert Enum.map(parts, & &1.amount) == [-2, -3]

    for amount <- [-1, -7, -100, -101, -999, -12_345], n <- 1..9 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount
    end
  end

  test "split/2 gives the extra minor unit to the first Integer.mod/2 parties for any sign" do
    # Shares are the floored base, with one extra minor unit handed to each of
    # the first `Integer.mod(amount, n)` parties -- so they always sum back,
    # for negative amounts just as much as for positive ones.
    amounts = [-12_345, -1000, -101, -100, -7, -5, -2, -1, 0, 1, 5, 7, 101, 1000]

    for amount <- amounts, n <- 1..9 do
      shares = Money.split(Money.new(amount, :USD), n) |> Enum.map(& &1.amount)

      base = Integer.floor_div(amount, n)
      remainder = Integer.mod(amount, n)
      expected = Enum.map(0..(n - 1), fn i -> if i < remainder, do: base + 1, else: base end)

      assert length(shares) == n
      assert shares == expected
      assert Enum.sum(shares) == amount
    end
  end

  # -------------------------------------------------------
  # to_string/1
  # -------------------------------------------------------

  test "to_string/1 formats 2-decimal currencies" do
    assert Money.to_string(Money.new(12345, :USD)) == "123.45 USD"
    assert Money.to_string(Money.new(5, :USD)) == "0.05 USD"
    assert Money.to_string(Money.new(-5, :USD)) == "-0.05 USD"
  end

  test "to_string/1 formats zero-decimal currencies without a point" do
    assert Money.to_string(Money.new(500, :JPY)) == "500 JPY"
    assert Money.to_string(Money.new(0, :JPY)) == "0 JPY"
  end

  test "to_string/1 formats 3-decimal currencies" do
    assert Money.to_string(Money.new(1_234_567, :BHD)) == "1234.567 BHD"
    assert Money.to_string(Money.new(7, :KWD)) == "0.007 KWD"
  end

  # -------------------------------------------------------
  # Integration
  # -------------------------------------------------------

  test "round-trip from_major then to_string is stable" do
    m = Money.from_major(19.99, :USD)
    assert m.amount == 1999
    assert Money.to_string(m) == "19.99 USD"
  end

  test "chained operations behave consistently" do
    # TODO
  end

  test "multiply/2 rounds halves away from zero for negative amounts too" do
    assert Money.multiply(Money.new(-101, :USD), 0.5).amount == -51
    assert Money.multiply(Money.new(101, :USD), -0.5).amount == -51
    assert Money.multiply(Money.new(-100, :JPY), 3).amount == -300
    assert is_integer(Money.multiply(Money.new(-101, :USD), 0.5).amount)
  end

  test "from_major/2 rounds negative halves away from zero" do
    assert Money.from_major(-0.005, :USD).amount == -1
    assert Money.from_major(-1.2345, :BHD).amount == -1235
    assert is_integer(Money.from_major(-0.005, :USD).amount)
  end

  test "split/2 raises when n is a non-integer or negative" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 1.5) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 2.0) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), -3) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), :two) end
  end

  test "exponent/1 knows every currency in the table, including EUR and GBP" do
    assert Money.exponent(:EUR) == 2
    assert Money.exponent(:GBP) == 2
    assert Money.from_major(123.45, :EUR).amount == 12_345
    assert Money.to_string(Money.new(12_345, :GBP)) == "123.45 GBP"
  end

  test "to_string/1 signs negative zero-decimal and 3-decimal amounts" do
    assert Money.to_string(Money.new(-500, :JPY)) == "-500 JPY"
    assert Money.to_string(Money.new(-1_234_567, :BHD)) == "-1234.567 BHD"
    assert Money.to_string(Money.new(-7, :KWD)) == "-0.007 KWD"
  end

  test "Money struct exposes exactly the amount and currency fields" do
    m = Money.new(12_345, :USD)
    assert m.__struct__ == Money
    assert m |> Map.from_struct() |> Map.keys() |> Enum.sort() == [:amount, :currency]
  end
end
```
