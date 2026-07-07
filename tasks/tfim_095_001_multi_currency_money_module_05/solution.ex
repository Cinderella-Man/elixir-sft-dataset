  test "new/2 raises when amount is not an integer" do
    assert_raise ArgumentError, fn -> Money.new(1.5, :USD) end
    assert_raise ArgumentError, fn -> Money.new("100", :USD) end
  end