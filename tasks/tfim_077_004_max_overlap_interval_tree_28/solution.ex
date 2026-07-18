  test "two divergent branches grown from one tree never disturb each other" do
    base = Enum.reduce(1..8, T.new(), fn i, acc -> T.insert(acc, {i, i + 1}) end)

    assert T.max_overlap(base) == 2
    assert T.busiest_point(base) == 2

    left = Enum.reduce(1..5, base, fn _, acc -> T.insert(acc, {1, 1}) end)
    right = Enum.reduce(1..5, base, fn _, acc -> T.insert(acc, {9, 9}) end)

    assert T.depth_at(left, 1) == 6
    assert T.max_overlap(left) == 6
    assert T.busiest_point(left) == 1
    assert T.depth_at(left, 9) == 1

    assert T.depth_at(right, 9) == 6
    assert T.max_overlap(right) == 6
    assert T.busiest_point(right) == 9
    assert T.depth_at(right, 1) == 1

    # The shared ancestor is unchanged by either branch.
    assert T.max_overlap(base) == 2
    assert T.busiest_point(base) == 2
    assert T.depth_at(base, 1) == 1
    assert T.depth_at(base, 9) == 1
  end