  test "aggregates stay correct through every rotation case" do
    # Each insertion order drives one of the four AVL fix-ups
    # (right-right, left-left, right-left, left-right).
    orders = [
      [{1, 1}, {2, 2}, {3, 3}],
      [{3, 3}, {2, 2}, {1, 1}],
      [{1, 1}, {3, 3}, {2, 2}],
      [{3, 3}, {1, 1}, {2, 2}]
    ]

    for order <- orders do
      tree = Enum.reduce(order, T.new(), &T.insert(&2, &1))

      assert T.depth_at(tree, 1) == 1
      assert T.depth_at(tree, 2) == 1
      assert T.depth_at(tree, 3) == 1
      assert T.depth_at(tree, 0) == 0
      assert T.depth_at(tree, 4) == 0
      assert T.max_overlap(tree) == 1
      assert T.busiest_point(tree) == 1
    end
  end