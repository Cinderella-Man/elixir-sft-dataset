  test "new/2 raises on unsupported currency" do
    assert_raise ArgumentError, fn -> Money.new(100, :XYZ) end
  end