  test "touching intervals overlap at the shared endpoint" do
    tree =
      T.new()
      |> T.insert({1, 5})
      |> T.insert({5, 10})

    assert T.depth_at(tree, 5) == 2
    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == 5
  end