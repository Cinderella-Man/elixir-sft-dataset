  test "single interval has max overlap of one at its start" do
    tree = T.new() |> T.insert({3, 7})
    assert T.max_overlap(tree) == 1
    assert T.busiest_point(tree) == 3
  end