  test "single interval does not cover points outside it" do
    tree = T.new() |> T.insert({3, 7})
    assert T.depth_at(tree, 2) == 0
    assert T.depth_at(tree, 8) == 0
  end