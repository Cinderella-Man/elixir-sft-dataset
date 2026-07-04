  test "removing non-member raises ArgumentError", %{s: s} do
    assert_raise ArgumentError, fn ->
      ORSet.remove(s, :never_added)
    end
  end