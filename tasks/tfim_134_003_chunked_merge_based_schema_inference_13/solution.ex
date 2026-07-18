  test "an empty fragment has nil names, zero ncols and no categories" do
    empty = MergeSchema.partial("")
    newline_only = MergeSchema.partial("\n")

    assert empty.names == nil
    assert empty.ncols == 0
    assert empty.categories == %{}

    assert newline_only.names == nil
    assert newline_only.ncols == 0
    assert newline_only.categories == %{}
  end