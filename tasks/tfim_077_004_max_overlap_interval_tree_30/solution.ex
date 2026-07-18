  test "repeated degenerate intervals at one coordinate stack with touching neighbours" do
    tree =
      T.new()
      |> T.insert({0, 4})
      |> T.insert({4, 4})
      |> T.insert({4, 4})
      |> T.insert({4, 9})

    assert T.depth_at(tree, 3) == 1
    assert T.depth_at(tree, 4) == 4
    assert T.depth_at(tree, 5) == 1
    assert T.depth_at(tree, 9) == 1
    assert T.depth_at(tree, 10) == 0
    assert T.max_overlap(tree) == 4
    assert T.busiest_point(tree) == 4
  end