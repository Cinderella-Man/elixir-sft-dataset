  test "validation errors map the input string key to a list of message strings" do
    results =
      ConcurrentCatalog.bulk_create([
        %{"name" => "Priced wrong", "price" => 0},
        %{"name" => "", "price" => 3}
      ])

    assert {0, :error, {:validation, price_errors}} = Enum.at(results, 0)
    assert Map.keys(price_errors) == ["price"]
    assert [_ | _] = price_errors["price"]
    assert Enum.all?(price_errors["price"], &is_binary/1)

    assert {1, :error, {:validation, name_errors}} = Enum.at(results, 1)
    assert Map.keys(name_errors) == ["name"]
    assert [_ | _] = name_errors["name"]
    assert Enum.all?(name_errors["name"], &is_binary/1)

    assert ConcurrentCatalog.count() == 0
    assert ConcurrentCatalog.all() == []
  end