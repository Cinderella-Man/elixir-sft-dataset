  test "infer_file reads and infers from a file on disk" do
    path =
      Path.join(
        System.tmp_dir!(),
        "schema_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, """
    id,price,label
    1,9.99,"A,B"
    2,19.99,C
    """)

    on_exit(fn -> File.rm(path) end)

    assert SchemaInference.infer_file(path) == %{
             "id" => :integer,
             "price" => :float,
             "label" => :string
           }
  end