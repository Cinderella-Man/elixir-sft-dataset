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

  test "split/2 floors for negative amounts so shares still sum back" do
    parts = Money.split(Money.new(-5, :USD), 2)
    assert Enum.map(parts, & &1.amount) == [-2, -3]

    for amount <- [-1, -7, -100, -101, -999, -12_345], n <- 1..9 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount
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
    total =
      Money.from_major(10.00, :USD)
      |> Money.add(Money.new(500, :USD))
      |> Money.multiply(2)

    assert total.amount == 3000
    assert Money.to_string(total) == "30.00 USD"
  end
end
