  test "insert is non-destructive" do
    t0 = T.new()
    t1 = T.insert(t0, {1, 5})
    t2 = T.insert(t1, {1, 5})

    assert T.max_overlap(t0) == 0
    assert T.depth_at(t0, 3) == 0

    assert T.max_overlap(t1) == 1
    assert T.depth_at(t1, 3) == 1

    assert T.max_overlap(t2) == 2
    assert T.depth_at(t2, 3) == 2
  end