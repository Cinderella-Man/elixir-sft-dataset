  test "imports a fully valid CSV" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,95.5,true
    Bob,bob@test.org,25,88.0,false
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [alice, bob] = valid
    assert alice["name"] == "Alice"
    assert alice["email"] == "alice@example.com"
    assert alice["age"] == "30"
    assert bob["active"] == "false"
  end