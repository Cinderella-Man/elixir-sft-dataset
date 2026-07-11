  test "merge is commutative at the finalized level" do
    a = MergeSchema.partial("v\n1\nhello\n")
    b = MergeSchema.partial("2\nworld\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) ==
             MergeSchema.finalize(MergeSchema.merge(b, a))
  end