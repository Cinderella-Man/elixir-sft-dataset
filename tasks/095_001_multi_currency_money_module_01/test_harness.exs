Code.require_file("solution.ex", __DIR__)

defmodule MoneyTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # new/2
  # -------------------------------------------------------

  test "new/2 builds a struct with amount and currency" do
    m = Money.new(100, :USD)
    assert m.amount == 100
    assert m.currency == :USD
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