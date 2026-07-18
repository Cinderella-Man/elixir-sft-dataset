  test "convert/3 to the same currency is a no-op amount" do
    result = Money.convert(Money.new(80, :USD), :USD, @rates)
    assert result.amount == 80
    assert result.currency == :USD
  end