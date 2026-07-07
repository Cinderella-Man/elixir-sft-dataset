  test "convert/3 USD to EUR rounds correctly" do
    result = Money.convert(Money.new(100, :USD), :EUR, @rates)
    assert result.amount == 91
    assert result.currency == :EUR
  end