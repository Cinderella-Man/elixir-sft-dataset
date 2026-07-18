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