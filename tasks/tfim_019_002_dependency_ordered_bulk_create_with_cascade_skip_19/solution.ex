  test "skipped ancestor is the nearest skipped ancestor, not the root invalid item" do
    # Chain: invalid@0 -> 1 -> 2 -> 3. Each skipped item must report its own
    # nearest bad/skipped ancestor, which for 2 and 3 is a *skipped* item.
    items = [
      %{"name" => "", "ref" => "bad"},
      %{"name" => "mid one", "ref" => "m1", "parent" => "bad"},
      %{"name" => "mid two", "ref" => "m2", "parent" => "m1"},
      %{"name" => "leaf", "parent" => "m2"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, {:validation, _}} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, 1} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert {3, :skipped, 2} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert Catalog.count() == 0
    assert Catalog.all() == []
  end