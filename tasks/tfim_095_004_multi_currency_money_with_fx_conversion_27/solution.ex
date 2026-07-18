  test "convert/3 raises for an unknown currency even when source and target match" do
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :JPY), :JPY, @rates) end
    assert_raise ArgumentError, fn -> Money.convert(Money.new(100, :CHF), :JPY, @rates) end
  end