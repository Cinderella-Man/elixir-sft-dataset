  test "inserting the same interval twice doubles the depth" do
    tree =
      T.new()
      |> T.insert({2, 8})
      |> T.insert({2, 8})

    assert T.depth_at(tree, 5) == 2
    assert T.max_overlap(tree) == 2
  end