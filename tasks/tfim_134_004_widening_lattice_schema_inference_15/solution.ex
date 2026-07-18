  test "infer_file reads and infers from a file on disk" do
    path =
      Path.join(
        System.tmp_dir!(),
        "lattice_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, """
    id,when
    1,2020-01-15
    2,2020-01-15T10:00:00
    """)

    on_exit(fn -> File.rm(path) end)

    assert LatticeSchema.infer_file(path) == %{
             "id" => :integer,
             "when" => :datetime
           }
  end