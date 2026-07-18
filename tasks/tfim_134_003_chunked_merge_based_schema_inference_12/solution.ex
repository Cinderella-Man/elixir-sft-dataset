  test "ncols takes the max across ragged chunks" do
    a = MergeSchema.partial("1\n", headers: false)
    b = MergeSchema.partial("2,3,4\n", headers: false)

    merged = MergeSchema.merge(a, b)
    assert merged.ncols == 3

    assert MergeSchema.finalize(merged) == %{
             "column_1" => :integer,
             "column_2" => :integer,
             "column_3" => :integer
           }
  end