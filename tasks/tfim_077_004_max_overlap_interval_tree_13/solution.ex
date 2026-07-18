  test "busiest point is the leftmost of several maxima" do
    # Two disjoint clusters each stack to depth 2.
    tree =
      T.new()
      |> T.insert({1, 3})
      |> T.insert({2, 4})
      |> T.insert({10, 12})
      |> T.insert({11, 13})

    assert T.max_overlap(tree) == 2
    assert T.busiest_point(tree) == 2
  end