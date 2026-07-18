  test "max overlap and busiest point of nested intervals" do
    tree =
      T.new()
      |> T.insert({1, 10})
      |> T.insert({2, 6})
      |> T.insert({3, 4})

    assert T.max_overlap(tree) == 3
    assert T.busiest_point(tree) == 3
  end