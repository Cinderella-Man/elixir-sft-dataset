  test "three copies of one interval stack to depth three at the leftmost busiest point" do
    tree = Enum.reduce(1..3, T.new(), fn _, acc -> T.insert(acc, {2, 8}) end)

    assert T.depth_at(tree, 1) == 0
    assert T.depth_at(tree, 2) == 3
    assert T.depth_at(tree, 8) == 3
    assert T.depth_at(tree, 9) == 0
    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 2
  end