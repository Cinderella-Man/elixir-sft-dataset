  test "large timestamps work correctly", %{s: s} do
    LWWSet.add(s, :a, 1_000_000)
    LWWSet.remove(s, :a, 999_999)
    assert LWWSet.member?(s, :a) == true
  end