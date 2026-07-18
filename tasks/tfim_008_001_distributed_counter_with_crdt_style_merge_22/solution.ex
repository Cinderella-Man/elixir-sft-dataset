  test "increment with non-positive amount raises", %{c: c} do
    assert_raise ArgumentError, fn ->
      Counter.increment(c, :a, 0)
    end

    assert_raise ArgumentError, fn ->
      Counter.increment(c, :a, -1)
    end
  end