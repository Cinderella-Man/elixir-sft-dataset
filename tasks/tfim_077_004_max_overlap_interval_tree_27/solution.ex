  test "abutting intervals whose deltas cancel at a shared coordinate keep depth one" do
    # [1,5] ends at coordinate 6 exactly where [6,10] begins, so that coordinate
    # carries a net delta of zero and must not erase the coverage there.
    tree =
      T.new()
      |> T.insert({1, 5})
      |> T.insert({6, 10})

    assert T.depth_at(tree, 0) == 0
    assert T.depth_at(tree, 5) == 1
    assert T.depth_at(tree, 6) == 1
    assert T.depth_at(tree, 10) == 1
    assert T.depth_at(tree, 11) == 0
    assert T.max_overlap(tree) == 1
    assert T.busiest_point(tree) == 1
  end