  test "partial exposes the documented representation" do
    p = MergeSchema.partial("n\n1\n2\n")
    assert p.names == ["n"]
    assert p.ncols == 1
    assert p.categories == %{0 => MapSet.new([:integer])}
  end