  test "infer_file forwards options to infer_string" do
    path =
      Path.join(
        System.tmp_dir!(),
        "schema_opts_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, "1,2.5\n3,4.5\n")
    on_exit(fn -> File.rm(path) end)

    assert SchemaInference.infer_file(path, headers: false) == %{
             "column_1" => :integer,
             "column_2" => :float
           }
  end