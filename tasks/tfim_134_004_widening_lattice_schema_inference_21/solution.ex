  test "infer_file honors headers and sample_rows options like infer_string" do
    path =
      Path.join(
        System.tmp_dir!(),
        "lattice_opts_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    contents = """
    2020-01-15,1
    2020-01-15T10:00:00,2
    """

    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    opts = [headers: false, sample_rows: 1]

    assert LatticeSchema.infer_file(path, opts) ==
             LatticeSchema.infer_string(contents, opts)

    assert LatticeSchema.infer_file(path, opts) ==
             %{"column_1" => :date, "column_2" => :integer}
  end