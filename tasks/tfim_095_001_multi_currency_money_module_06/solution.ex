  test "new/2 raises when currency is not an atom" do
    assert_raise ArgumentError, fn -> Money.new(100, "USD") end
  end