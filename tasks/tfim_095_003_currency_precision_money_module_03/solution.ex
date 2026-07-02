  test "exponent/1 raises on unsupported currency" do
    assert_raise ArgumentError, fn -> Money.exponent(:XYZ) end
  end