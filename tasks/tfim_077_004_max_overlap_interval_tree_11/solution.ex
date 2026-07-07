  test "nested intervals accumulate depth" do
    tree =
      T.new()
      |> T.insert({1, 10})
      |> T.insert({2, 6})
      |> T.insert({3, 4})

    assert T.depth_at(tree, 1) == 1
    assert T.depth_at(tree, 2) == 2
    assert T.depth_at(tree, 3) == 3
    assert T.depth_at(tree, 4) == 3
    assert T.depth_at(tree, 5) == 2
    assert T.depth_at(tree, 7) == 1
    assert T.depth_at(tree, 11) == 0
  end