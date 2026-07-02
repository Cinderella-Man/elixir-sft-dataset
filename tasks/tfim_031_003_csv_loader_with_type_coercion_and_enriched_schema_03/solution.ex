  test "valid rows use atom keys" do
    csv = """
    name,age,active,joined
    Carol,40,1,2020-03-10
    """

    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert is_map(row)
    assert Map.has_key?(row, :name)
    assert Map.has_key?(row, :age)
    assert Map.has_key?(row, :active)
    assert Map.has_key?(row, :joined)
  end