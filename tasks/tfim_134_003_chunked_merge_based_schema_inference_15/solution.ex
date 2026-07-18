  test "ncols is the max of header length and data row widths within one fragment" do
    wide_header = MergeSchema.partial("a,b,c\n1,2\n")
    assert wide_header.ncols == 3

    wide_data = MergeSchema.partial("a\n1,2,3\n")
    assert wide_data.ncols == 3
  end