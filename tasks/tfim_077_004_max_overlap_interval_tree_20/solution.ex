  test "max overlap survives a randomized-order insertion" do
    intervals = [
      {5, 9},
      {1, 3},
      {2, 8},
      {7, 7},
      {0, 10},
      {3, 4},
      {8, 12},
      {2, 2}
    ]

    tree = Enum.reduce(intervals, T.new(), &T.insert(&2, &1))

    # Brute-force reference over a bounded coordinate window.
    reference =
      for p <- -2..15 do
        Enum.count(intervals, fn {s, f} -> s <= p and p <= f end)
      end

    expected_max = Enum.max(reference)

    assert T.max_overlap(tree) == expected_max
    assert T.depth_at(tree, T.busiest_point(tree)) == expected_max
  end