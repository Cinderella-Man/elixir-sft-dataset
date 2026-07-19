# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), 2.0) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), -3) end
    assert_raise ArgumentError, fn -> Money.split(Money.new(100, :USD), :two) end
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
