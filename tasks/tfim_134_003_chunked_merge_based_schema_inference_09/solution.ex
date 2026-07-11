  test "mixing incompatible categories across chunks resolves to string" do
    a = MergeSchema.partial("x\n2020-01-15\n")
    b = MergeSchema.partial("2020-01-15T10:00:00\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) == %{"x" => :string}
  end