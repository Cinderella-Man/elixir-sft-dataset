  test "reports validation errors per index and still creates the rest" do
    items = [
      %{"name" => "", "price" => 10},
      %{"name" => "Good", "price" => 5},
      %{"name" => "Bad", "price" => -1}
    ]

    results = ConcurrentCatalog.bulk_create(items)

    assert {0, :error, {:validation, e0}} = Enum.at(results, 0)
    assert Map.has_key?(e0, "name")
    assert {1, :ok, _} = Enum.at(results, 1)
    assert {2, :error, {:validation, e2}} = Enum.at(results, 2)
    assert Map.has_key?(e2, "price")

    assert ConcurrentCatalog.count() == 1
    assert [%{name: "Good"}] = ConcurrentCatalog.all()
  end