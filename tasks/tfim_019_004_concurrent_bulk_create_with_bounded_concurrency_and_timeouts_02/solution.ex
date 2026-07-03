  test "creates all valid items with results in original order" do
    items = [
      %{"name" => "Alpha", "price" => 10},
      %{"name" => "Beta", "price" => 20},
      %{"name" => "Gamma", "price" => 30}
    ]

    results = ConcurrentCatalog.bulk_create(items)
    assert length(results) == 3

    for {i, expected} <- [{0, "Alpha"}, {1, "Beta"}, {2, "Gamma"}] do
      assert {^i, :ok, item} = Enum.at(results, i)
      assert item.name == expected
      assert is_integer(item.id)
    end

    assert ConcurrentCatalog.count() == 3

    all = ConcurrentCatalog.all()
    assert is_list(all)
    assert length(all) == 3
    assert Enum.sort(Enum.map(all, & &1.name)) == ["Alpha", "Beta", "Gamma"]
    assert Enum.sort(Enum.map(all, & &1.price)) == [10, 20, 30]

    for item <- all do
      assert %{id: id, name: name, price: price} = item
      assert is_integer(id)
      assert is_binary(name)
      assert is_integer(price)
      assert ConcurrentCatalog.get(id) == item
    end
  end