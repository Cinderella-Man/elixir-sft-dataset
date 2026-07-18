  test "an empty fragment is a neutral element for merge in both orders" do
    empty = MergeSchema.partial("")
    p = MergeSchema.partial("n,m\n1,2.5\n")

    expected = MergeSchema.finalize(p)
    assert expected == %{"n" => :integer, "m" => :float}

    assert MergeSchema.finalize(MergeSchema.merge(empty, p)) == expected
    assert MergeSchema.finalize(MergeSchema.merge(p, empty)) == expected
  end