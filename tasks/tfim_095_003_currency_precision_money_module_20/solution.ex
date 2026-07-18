  test "to_string/1 formats 2-decimal currencies" do
    assert Money.to_string(Money.new(12345, :USD)) == "123.45 USD"
    assert Money.to_string(Money.new(5, :USD)) == "0.05 USD"
    assert Money.to_string(Money.new(-5, :USD)) == "-0.05 USD"
  end