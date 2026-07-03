  test "all/0 reflects the store contents and is empty initially" do
    assert ConcurrentCatalog.all() == []

    ConcurrentCatalog.bulk_create([%{"name" => "Solo", "price" => 7}])

    assert [%{id: id, name: "Solo", price: 7}] = ConcurrentCatalog.all()
    assert ConcurrentCatalog.get(id) == %{id: id, name: "Solo", price: 7}
  end