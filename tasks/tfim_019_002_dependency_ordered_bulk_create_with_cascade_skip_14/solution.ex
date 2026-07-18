  test "partial mode marks only cycle members as :cycle and downstream items as skipped" do
    items = [
      %{"name" => "a", "ref" => "a", "parent" => "b"},
      %{"name" => "b", "ref" => "b", "parent" => "a"},
      %{"name" => "downstream", "parent" => "a"},
      %{"name" => "free"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert {3, :ok, created} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert created.name == "free"
    assert created.parent_id == nil
    assert Catalog.count() == 1
    assert [^created] = Catalog.all()
  end