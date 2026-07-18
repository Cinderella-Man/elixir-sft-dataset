  test "convert round-trip is approximately identity within rounding" do
    eur = Money.convert(Money.new(100, :USD), :EUR, @rates)
    back = Money.convert(eur, :USD, @rates)
    # 100 -> 91 EUR -> 100 USD (91 * 1.10 / 1.0 = 100.1 -> 100)
    assert back.amount == 100
  end