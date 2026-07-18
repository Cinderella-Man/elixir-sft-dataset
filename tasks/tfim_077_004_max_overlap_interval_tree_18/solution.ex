  test "handles negative coordinates" do
    tree =
      T.new()
      |> T.insert({-10, -5})
      |> T.insert({-7, -1})

    assert T.depth_at(tree, -7) == 2
    assert T.depth_at(tree, -6) == 2
    assert T.depth_at(tree, -5) == 2
    assert T.depth_at(tree, -4) == 1
    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == -7
  end