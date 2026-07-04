  test "insert failures are reported per index" do
    items = [
      %{"name" => "a", "price" => 1, "fail" => true},
      %{"name" => "b", "price" => 2}
    ]

    results = ConcurrentCatalog.bulk_create(items)

    assert {0, :error, :insert_failed} = Enum.at(results, 0)
    assert {1, :ok, _} = Enum.at(results, 1)
    assert ConcurrentCatalog.count() == 1
    assert [%{name: "b"}] = ConcurrentCatalog.all()
  end