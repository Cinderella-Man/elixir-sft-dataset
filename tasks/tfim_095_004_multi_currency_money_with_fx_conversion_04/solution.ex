  test "new/2 raises on bad types" do
    assert_raise ArgumentError, fn -> Money.new(1.5, :USD) end
    assert_raise ArgumentError, fn -> Money.new(100, "USD") end
  end