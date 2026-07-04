  test "remove-wins on equal timestamps (tie-breaking)", %{s: s} do
    LWWSet.add(s, :x, 5)
    LWWSet.remove(s, :x, 5)
    assert LWWSet.member?(s, :x) == false
  end