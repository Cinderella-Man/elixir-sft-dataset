  test "all/0 returns exactly the stored items" do
    # Empty store first.
    assert Catalog.all() == []

    items = [%{"name" => "Alpha"}, %{"name" => "Beta"}, %{"name" => "Gamma"}]
    assert {:ok, results} = Catalog.bulk_create(items)

    stored = Catalog.all()
    assert is_list(stored)
    assert length(stored) == 3

    # all/0 must return the same item maps that were created.
    created_maps = Enum.map([0, 1, 2], &item(results, &1))
    assert Enum.sort_by(stored, & &1.id) == Enum.sort_by(created_maps, & &1.id)

    assert MapSet.new(stored, & &1.name) == MapSet.new(["Alpha", "Beta", "Gamma"])
    assert Enum.all?(stored, &is_map/1)

    # get/1 for every id returned by all/0 must round-trip.
    for it <- stored do
      assert Catalog.get(it.id) == it
    end
  end