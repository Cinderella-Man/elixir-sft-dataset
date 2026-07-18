  test "to_string/1 formats zero-decimal currencies without a point" do
    assert Money.to_string(Money.new(500, :JPY)) == "500 JPY"
    assert Money.to_string(Money.new(0, :JPY)) == "0 JPY"
  end