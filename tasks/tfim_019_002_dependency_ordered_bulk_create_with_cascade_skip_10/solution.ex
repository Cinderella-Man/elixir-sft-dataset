  test "partial mode skips invalid items and their dependents but creates independents" do
    items = [
      %{"name" => "", "ref" => "bad"},
      %{"name" => "dependent", "parent" => "bad"},
      %{"name" => "independent"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)
    assert Catalog.count() == 1

    # all/0 must contain exactly the one created item.
    assert [only] = Catalog.all()
    assert only.name == "independent"

    assert {0, :error, {:validation, _}} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :ok, item} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert item.name == "independent"
    assert only == item
  end