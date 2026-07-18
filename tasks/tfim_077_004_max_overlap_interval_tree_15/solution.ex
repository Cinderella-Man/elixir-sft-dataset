  test "degenerate interval stacks with an enclosing interval" do
    tree =
      T.new()
      |> T.insert({0, 10})
      |> T.insert({5, 5})

    assert T.depth_at(tree, 5) == 2
    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == 5
  end