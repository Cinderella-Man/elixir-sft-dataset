  test "date coercion returns Date struct" do
    csv = "name,age,active,joined\nAlice,30,true,2024-12-25\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.joined == ~D[2024-12-25]
  end