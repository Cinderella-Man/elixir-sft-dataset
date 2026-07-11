  test "header-only fragment yields all-string columns" do
    assert MergeSchema.infer_string("a,b,c\n") == %{
             "a" => :string,
             "b" => :string,
             "c" => :string
           }
  end