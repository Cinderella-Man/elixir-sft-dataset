  test "infer_file reads and profiles from a file on disk" do
    path =
      Path.join(
        System.tmp_dir!(),
        "profile_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, """
    id,label
    1,a
    2,a
    """)

    on_exit(fn -> File.rm(path) end)

    assert SchemaProfiler.infer_file(path) == %{
             "id" => %{type: :integer, nullable: false, unique: true},
             "label" => %{type: :string, nullable: false, unique: false}
           }
  end