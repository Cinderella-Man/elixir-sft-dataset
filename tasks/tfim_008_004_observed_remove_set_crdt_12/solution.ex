  test "multiple elements tracked independently", %{s: s} do
    ORSet.add(s, :a, :n1)
    ORSet.add(s, :b, :n1)
    ORSet.add(s, :c, :n1)
    ORSet.remove(s, :b)

    assert ORSet.members(s) == MapSet.new([:a, :c])
  end