  test "new/2 builds a struct" do
    m = Money.new(100, :USD)
    assert m.amount == 100
    assert m.currency == :USD
  end