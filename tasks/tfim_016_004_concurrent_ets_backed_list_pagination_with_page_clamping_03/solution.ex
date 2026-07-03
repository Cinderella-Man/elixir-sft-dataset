  test "later inserts overwrite same id and count reflects uniqueness" do
    table = EtsCatalog.new()
    EtsCatalog.insert(table, %{id: 1, name: "old"})
    EtsCatalog.insert(table, %{id: 1, name: "new"})

    assert EtsCatalog.count(table) == 1
    %{data: [item]} = EtsCatalog.list(table)
    assert item.name == "new"
  end