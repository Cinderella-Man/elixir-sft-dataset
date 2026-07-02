  test "imports a fully valid CSV with correctly typed values" do
    csv = """
    name,age,score,active,joined
    Alice,30,95.5,true,2024-01-15
    Bob,25,88.0,false,2023-06-01
    """

    assert {:ok, valid, errors} = CsvLoader.load_string(csv, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [alice, bob] = valid
    assert alice.name == "Alice"
    assert alice.age == 30
    assert is_integer(alice.age)
    assert alice.score == 95.5
    assert is_float(alice.score)
    assert alice.active == true
    assert alice.joined == ~D[2024-01-15]
    assert bob.active == false
  end