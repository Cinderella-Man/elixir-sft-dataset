  test "merge is idempotent" do
    p = MergeSchema.partial("d\n2020-01-15\n03/25/2021\n")

    assert MergeSchema.merge(p, p) == p
    assert MergeSchema.finalize(MergeSchema.merge(p, p)) == MergeSchema.finalize(p)
  end