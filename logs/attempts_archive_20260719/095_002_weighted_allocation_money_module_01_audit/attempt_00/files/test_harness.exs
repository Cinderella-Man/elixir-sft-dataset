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

  test "new/2 allows negative amounts and zero" do
    assert Money.new(-250, :EUR).amount == -250
    assert Money.new(0, :JPY).amount == 0
  end

  test "new/2 raises on bad types" do
    assert_raise ArgumentError, fn -> Money.new(1.5, :USD) end
    assert_raise ArgumentError, fn -> Money.new(100, "USD") end
  end

  # -------------------------------------------------------
  # add/2 & subtract/2
  # -------------------------------------------------------

  test "add/2 sums same-currency values" do
    result = Money.add(Money.new(100, :USD), Money.new(250, :USD))
    assert result.amount == 350
    assert result.currency == :USD
  end

  test "subtract/2 can produce a negative result" do
    result = Money.subtract(Money.new(200, :USD), Money.new(500, :USD))
    assert result.amount == -300
  end

  test "add/2 and subtract/2 raise on currency mismatch" do
    assert_raise ArgumentError, fn -> Money.add(Money.new(1, :USD), Money.new(1, :EUR)) end
    assert_raise ArgumentError, fn -> Money.subtract(Money.new(1, :USD), Money.new(1, :GBP)) end
  end

  # -------------------------------------------------------
  # multiply/2
  # -------------------------------------------------------

  test "multiply/2 rounds halves away from zero" do
    assert Money.multiply(Money.new(101, :USD), 0.5).amount == 51
    assert Money.multiply(Money.new(100, :USD), 0.005).amount == 1
  end

  test "multiply/2 preserves currency" do
    assert Money.multiply(Money.new(500, :EUR), 2).currency == :EUR
  end

  # -------------------------------------------------------
  # allocate/2
  # -------------------------------------------------------

  test "allocate/2 divides by weights that sum cleanly" do
    parts = Money.allocate(Money.new(100, :USD), [3, 7])
    assert Enum.map(parts, & &1.amount) == [30, 70]
    assert Enum.all?(parts, &(&1.currency == :USD))
  end

  test "allocate/2 distributes the remainder to the earliest parties" do
    parts = Money.allocate(Money.new(10, :USD), [1, 1, 1, 1])
    assert Enum.map(parts, & &1.amount) == [3, 3, 2, 2]
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 10
  end

  test "allocate/2 with equal weights matches the canonical thirds example" do
    parts = Money.allocate(Money.new(1000, :USD), [1, 1, 1])
    assert Enum.map(parts, & &1.amount) == [334, 333, 333]
  end

  test "allocate/2 respects weight proportions with a remainder" do
    # 100 by [1,2]: shares 33 and 66 (sum 99), remainder 1 -> first party
    parts = Money.allocate(Money.new(100, :USD), [1, 2])
    assert Enum.map(parts, & &1.amount) == [34, 66]
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 100
  end

  test "allocate/2 handles negative amounts and still sums back" do
    parts = Money.allocate(Money.new(-10, :USD), [1, 1, 1])
    amounts = Enum.map(parts, & &1.amount)
    assert Enum.sum(amounts) == -10
    assert Enum.max(amounts) - Enum.min(amounts) <= 1
    assert amounts == [-4, -3, -3]
  end

  test "allocate/2 returns exactly one struct per weight" do
    assert length(Money.allocate(Money.new(1000, :USD), [1, 2, 3, 4, 5])) == 5
  end

  test "allocate/2 always sums back to the original amount" do
    for amount <- [0, 1, 7, 100, 101, 999, 12_345, -50, -333],
        ratios <- [[1], [1, 1], [1, 2, 3], [5, 1, 1], [2, 2, 2, 2], [1, 3, 5, 7]] do
      parts = Money.allocate(Money.new(amount, :USD), ratios)
      assert length(parts) == length(ratios)

      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount,
             "allocate(#{amount}, #{inspect(ratios)}) did not sum back"
    end
  end

  test "allocate/2 raises on invalid ratios" do
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), []) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), [0, 0]) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), [1, -1]) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), [1, 1.5]) end
    assert_raise ArgumentError, fn -> Money.allocate(Money.new(100, :USD), :nope) end
  end

  # -------------------------------------------------------
  # split/2
  # -------------------------------------------------------

  test "split/2 divides evenly and distributes remainder" do
    assert Enum.map(Money.split(Money.new(900, :USD), 3), & &1.amount) == [300, 300, 300]
    assert Enum.map(Money.split(Money.new(1000, :USD), 3), & &1.amount) == [334, 333, 333]
  end

  test "split/2 by 1 returns the whole amount" do
    assert Enum.map(Money.split(Money.new(1234, :USD), 1), & &1.amount) == [1234]
  end

  test "split/2 handles more parties than cents" do
    parts = Money.split(Money.new(2, :USD), 3)
    assert Enum.map(parts, & &1.amount) == [1, 1, 0]
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
    parts = Money.allocate(total, [1, 1, 1])
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 2600
  end

  test "new/2 produces a struct carrying exactly the amount and currency fields" do
    keys =
      Money.new(100, :USD)
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.sort()

    assert keys == [:amount, :currency]
  end

  test "split/2 raises when n is a non-integer number" do
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 3.0) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), :three) end
  end

  test "allocate/2 accepts zero weights and still pays remainder to the earliest party" do
    parts = Money.allocate(Money.new(10, :USD), [0, 1, 1, 1])
    amounts = Enum.map(parts, & &1.amount)
    assert amounts == [1, 3, 3, 3]
    assert Enum.sum(amounts) == 10
  end

  test "multiply/2 rounds a negative half away from zero" do
    assert Money.multiply(Money.new(101, :USD), -0.5).amount == -51
    assert Money.multiply(Money.new(-101, :USD), 0.5).amount == -51
  end
end
