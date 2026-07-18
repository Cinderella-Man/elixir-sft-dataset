  test "import_file reads and validates a real file" do
    path = "/tmp/csv_importer_test_#{:rand.uniform(999_999)}.csv"

    content = """
    name,email,age,active
    Alice,alice@example.com,30,true
    ,bad,nope,yes
    """

    File.write!(path, content)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, valid, errors} = CsvImporter.import_file(path, @basic_schema)
    assert length(valid) == 1
    assert length(errors) >= 3
  end