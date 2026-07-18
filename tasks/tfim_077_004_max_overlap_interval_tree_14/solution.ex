  test "degenerate interval covers exactly its point" do
    tree = T.new() |> T.insert({4, 4})
    assert T.depth_at(tree, 4) == 1
    assert T.depth_at(tree, 3) == 0
    assert T.depth_at(tree, 5) == 0
    assert T.max_overlap(tree) == 1
    assert T.busiest_point(tree) == 4
  end