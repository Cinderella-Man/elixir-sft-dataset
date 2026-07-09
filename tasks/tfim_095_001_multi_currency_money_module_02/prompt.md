# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MoneyTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # new/2
  # -------------------------------------------------------

  test "new/2 builds a struct with amount and currency" do
    # TODO
  end

  test "new/2 allows negative amounts (debts)" do
    m = Money.new(-250, :EUR)
    assert m.amount == -250
    assert m.currency == :EUR
  end

  test "new/2 allows zero" do
    assert Money.new(0, :JPY).amount == 0
  end

  test "new/2 raises when amount is not an integer" do
    assert_raise ArgumentError, fn -> Money.new(1.5, :USD) end
    assert_raise ArgumentError, fn -> Money.new("100", :USD) end
  end

  test "new/2 raises when currency is not an atom" do
    assert_raise ArgumentError, fn -> Money.new(100, "USD") end
  end

  # -------------------------------------------------------
  # add/2
  # -------------------------------------------------------

  test "add/2 sums two same-currency values" do
    result = Money.add(Money.new(100, :USD), Money.new(250, :USD))
    assert result.amount == 350
    assert result.currency == :USD
  end

  test "add/2 handles negative operands" do
    result = Money.add(Money.new(100, :USD), Money.new(-30, :USD))
    assert result.amount == 70
    assert result.currency == :USD
  end

  test "add/2 raises on currency mismatch" do
    assert_raise ArgumentError, fn ->
      Money.add(Money.new(100, :USD), Money.new(100, :EUR))
    end
  end

  # -------------------------------------------------------
  # subtract/2
  # -------------------------------------------------------

  test "subtract/2 subtracts two same-currency values" do
    result = Money.subtract(Money.new(500, :USD), Money.new(200, :USD))
    assert result.amount == 300
    assert result.currency == :USD
  end

  test "subtract/2 can produce a negative result" do
    result = Money.subtract(Money.new(200, :USD), Money.new(500, :USD))
    assert result.amount == -300
    assert result.currency == :USD
  end

  test "subtract/2 raises on currency mismatch" do
    assert_raise ArgumentError, fn ->
      Money.subtract(Money.new(500, :USD), Money.new(100, :GBP))
    end
  end

  # -------------------------------------------------------
  # multiply/2
  # -------------------------------------------------------

  test "multiply/2 by an integer" do
    result = Money.multiply(Money.new(100, :USD), 3)
    assert result.amount == 300
    assert result.currency == :USD
  end

  test "multiply/2 by a float" do
    result = Money.multiply(Money.new(100, :USD), 0.1)
    assert result.amount == 10
    assert result.currency == :USD
  end

  test "multiply/2 rounds halves away from zero" do
    # 101 * 0.5 = 50.5 -> 51
    assert Money.multiply(Money.new(101, :USD), 0.5).amount == 51
    # 100 * 0.005 = 0.5 -> 1
    assert Money.multiply(Money.new(100, :USD), 0.005).amount == 1
  end

  test "multiply/2 by zero yields zero" do
    assert Money.multiply(Money.new(999, :USD), 0).amount == 0
  end

  test "multiply/2 preserves currency" do
    assert Money.multiply(Money.new(500, :EUR), 2).currency == :EUR
  end

  # -------------------------------------------------------
  # split/2
  # -------------------------------------------------------

  test "split/2 divides evenly when it divides cleanly" do
    parts = Money.split(Money.new(900, :USD), 3)
    assert Enum.map(parts, & &1.amount) == [300, 300, 300]
  end

  test "split/2 distributes the remainder to the first parties" do
    parts = Money.split(Money.new(1000, :USD), 3)
    assert Enum.map(parts, & &1.amount) == [334, 333, 333]
  end

  test "split/2 of $10.00 three ways matches the canonical example" do
    parts = Money.split(Money.new(1000, :USD), 3)
    amounts = Enum.map(parts, & &1.amount)
    assert amounts == [334, 333, 333]
    assert Enum.sum(amounts) == 1000
  end

  test "split/2 returns exactly n parts" do
    assert length(Money.split(Money.new(1000, :USD), 7)) == 7
  end

  test "split/2 by 1 returns the original amount in a single-element list" do
    parts = Money.split(Money.new(1234, :USD), 1)
    assert Enum.map(parts, & &1.amount) == [1234]
  end

  test "split/2 preserves currency in every part" do
    parts = Money.split(Money.new(1000, :GBP), 3)
    assert Enum.all?(parts, &(&1.currency == :GBP))
  end

  test "split/2 handles more parties than cents" do
    # 2 cents among 3 -> [1, 1, 0]
    parts = Money.split(Money.new(2, :USD), 3)
    assert Enum.map(parts, & &1.amount) == [1, 1, 0]
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 2
  end

  test "split/2 of zero yields all zeros" do
    parts = Money.split(Money.new(0, :USD), 4)
    assert Enum.map(parts, & &1.amount) == [0, 0, 0, 0]
  end

  test "split/2 always sums back to the original amount" do
    for amount <- [0, 1, 2, 5, 7, 10, 99, 100, 101, 333, 1000, 9999, 12_345],
        n <- 1..13 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert length(parts) == n

      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount,
             "split(#{amount}, #{n}) did not sum back to #{amount}"

      assert Enum.all?(parts, &(&1.currency == :USD))
    end
  end

  test "split/2 amounts differ by at most one cent" do
    for amount <- [1, 7, 101, 1000, 9999], n <- 2..9 do
      amounts = Money.split(Money.new(amount, :USD), n) |> Enum.map(& &1.amount)

      assert Enum.max(amounts) - Enum.min(amounts) <= 1,
             "split(#{amount}, #{n}) produced uneven shares: #{inspect(amounts)}"
    end
  end

  test "split/2 raises when n is not a positive integer" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 0) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), -3) end
  end

  # -------------------------------------------------------
  # Integration
  # -------------------------------------------------------

  test "chained operations behave consistently" do
    total =
      Money.new(1000, :USD)
      |> Money.add(Money.new(500, :USD))
      |> Money.subtract(Money.new(200, :USD))
      |> Money.multiply(2)

    assert total.amount == 2600
    assert total.currency == :USD

    parts = Money.split(total, 3)
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 2600
  end
end
```
