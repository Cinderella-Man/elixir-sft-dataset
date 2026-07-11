  test "positional chunks merge and finalize with generated names" do
    a = MergeSchema.partial("1,2.5\n", headers: false)
    b = MergeSchema.partial("3,4.5\n", headers: false)

    assert MergeSchema.finalize(MergeSchema.merge(a, b)) == %{
             "column_1" => :integer,
             "column_2" => :float
           }
  end