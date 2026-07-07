  test "new/2 raises on non-integer amount" do
    assert_raise ArgumentError, fn -> Money.new(1.5, :USD) end
  end