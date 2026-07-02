  test "new/2 builds a struct from minor units" do
    m = Money.new(12345, :USD)
    assert m.amount == 12345
    assert m.currency == :USD
  end