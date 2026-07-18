  test "decrement with non-positive amount raises", %{c: c} do
    assert_raise ArgumentError, fn ->
      Counter.decrement(c, :a, 0)
    end

    assert_raise ArgumentError, fn ->
      Counter.decrement(c, :a, -5)
    end
  end