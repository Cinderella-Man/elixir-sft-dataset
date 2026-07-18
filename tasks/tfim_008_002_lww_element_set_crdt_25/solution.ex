  test "add with non-positive timestamp raises", %{s: s} do
    assert_raise ArgumentError, fn ->
      LWWSet.add(s, :x, 0)
    end

    assert_raise ArgumentError, fn ->
      LWWSet.add(s, :x, -1)
    end
  end