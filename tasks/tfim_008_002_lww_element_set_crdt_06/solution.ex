  test "remove before add (lower timestamp) does not prevent membership", %{s: s} do
    LWWSet.remove(s, :x, 1)
    LWWSet.add(s, :x, 5)
    assert LWWSet.member?(s, :x) == true
  end