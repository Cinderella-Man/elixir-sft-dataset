  test "point just past a touch has depth one" do
    tree =
      T.new()
      |> T.insert({1, 5})
      |> T.insert({5, 10})

    assert T.depth_at(tree, 4) == 1
    assert T.depth_at(tree, 6) == 1
  end