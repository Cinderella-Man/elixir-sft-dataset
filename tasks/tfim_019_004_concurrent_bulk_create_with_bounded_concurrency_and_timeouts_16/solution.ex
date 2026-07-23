  test "a name of exactly 100 characters is valid and 101 characters is not" do
    # Names are 1–100 characters: 100 is the last accepted length, 101 the
    # first rejected one, and the rejected item is never stored.
    ok_name = String.duplicate("a", 100)
    long_name = String.duplicate("a", 101)

    results =
      ConcurrentCatalog.bulk_create([
        %{"name" => ok_name, "price" => 1},
        %{"name" => long_name, "price" => 2}
      ])

    assert {0, :ok, item} = Enum.at(results, 0)
    assert item.name == ok_name

    assert {1, :error, {:validation, errors}} = Enum.at(results, 1)
    assert Map.keys(errors) == ["name"]
    assert [_ | _] = errors["name"]
    assert Enum.all?(errors["name"], &is_binary/1)

    assert ConcurrentCatalog.count() == 1
    assert [%{name: ^ok_name}] = ConcurrentCatalog.all()
  end