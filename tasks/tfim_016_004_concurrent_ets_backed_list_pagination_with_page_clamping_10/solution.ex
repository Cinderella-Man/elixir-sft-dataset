  test "insert returns :ok for both a new id and an overwriting id" do
    table = EtsCatalog.new()

    assert EtsCatalog.insert(table, %{id: 7, name: "first"}) == :ok
    assert EtsCatalog.insert(table, %{id: 7, name: "second"}) == :ok
    assert EtsCatalog.count(table) == 1
  end