  test "single interval covers its interior point" do
    tree = T.new() |> T.insert({3, 7})
    assert T.depth_at(tree, 5) == 1
  end