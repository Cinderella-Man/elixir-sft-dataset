  test "remove with non-positive timestamp raises", %{s: s} do
    assert_raise ArgumentError, fn ->
      LWWSet.remove(s, :x, 0)
    end

    assert_raise ArgumentError, fn ->
      LWWSet.remove(s, :x, -5)
    end
  end