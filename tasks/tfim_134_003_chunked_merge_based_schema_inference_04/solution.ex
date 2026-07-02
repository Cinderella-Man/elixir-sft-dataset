  test "a header chunk merges with a headerless data chunk to promote the type" do
    p1 = MergeSchema.partial("n\n1\n2\n")
    p2 = MergeSchema.partial("3.5\n", headers: false)

    merged = MergeSchema.merge(p1, p2)
    assert merged.names == ["n"]
    assert merged.categories == %{0 => MapSet.new([:integer, :float])}
    assert MergeSchema.finalize(merged) == %{"n" => :float}
  end