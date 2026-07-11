  test "quoted values stay strings after merging" do
    a = MergeSchema.partial("code\n\"123\"\n")
    b = MergeSchema.partial("\"456\"\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) == %{"code" => :string}
  end