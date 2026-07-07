  test "single interval covers its endpoints" do
    tree = T.new() |> T.insert({3, 7})
    assert T.depth_at(tree, 3) == 1
    assert T.depth_at(tree, 7) == 1
  end