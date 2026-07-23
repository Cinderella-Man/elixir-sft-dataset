  test "skipped ancestor below a cycle is the nearest skipped item, not a cycle member" do
    # Cycle on 0 and 1; 2 hangs off the cycle and 3 hangs off 2, so 3's nearest
    # bad/skipped ancestor is the skipped item 2.
    items = [
      %{"name" => "a", "ref" => "a", "parent" => "b"},
      %{"name" => "b", "ref" => "b", "parent" => "a"},
      %{"name" => "below", "ref" => "below", "parent" => "a"},
      %{"name" => "further below", "parent" => "below"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert {3, :skipped, 2} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert Catalog.count() == 0
    assert Catalog.all() == []
  end