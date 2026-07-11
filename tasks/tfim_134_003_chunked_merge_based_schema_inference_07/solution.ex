  test "merge is associative across three chunks" do
    a = MergeSchema.partial("val\n1\n")
    b = MergeSchema.partial("2\n", headers: false)
    c = MergeSchema.partial("3.5\n", headers: false)

    left = MergeSchema.merge(MergeSchema.merge(a, b), c)
    right = MergeSchema.merge(a, MergeSchema.merge(b, c))

    assert MergeSchema.finalize(left) == MergeSchema.finalize(right)
    assert MergeSchema.finalize(left) == %{"val" => :float}
  end