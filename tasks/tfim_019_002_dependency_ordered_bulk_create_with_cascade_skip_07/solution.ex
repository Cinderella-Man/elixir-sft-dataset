  test "all-or-nothing rolls back everything when a single item is invalid" do
    items = [%{"name" => "ok"}, %{"name" => ""}, %{"name" => "also ok"}]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0

    assert {1, :error, {:validation, errs}} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert Map.has_key?(errs, "name")

    # Valid items appear as validated-but-not-stored
    assert {0, :ok, :valid} = Enum.find(results, fn {i, _, _} -> i == 0 end)
  end