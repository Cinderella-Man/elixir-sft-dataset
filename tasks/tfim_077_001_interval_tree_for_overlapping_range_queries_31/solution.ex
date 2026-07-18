  test "zig-zag inserts keep every interval and every endpoint queryable" do
    ivs = zigzag(64)
    tree = build(ivs)

    assert Enum.sort(IntervalTree.overlapping(tree, {0, 10_000})) == Enum.sort(ivs)

    for {s, f} <- ivs do
      assert IntervalTree.enclosing(tree, s) == [{s, f}]
      assert IntervalTree.enclosing(tree, f) == [{s, f}]
    end
  end