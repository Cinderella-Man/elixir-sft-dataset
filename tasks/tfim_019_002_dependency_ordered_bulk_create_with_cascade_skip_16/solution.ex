  test "name of exactly 100 chars is valid while 101 chars is a validation error" do
    items = [
      %{"name" => String.duplicate("a", 100)},
      %{"name" => String.duplicate("b", 101)}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    ok = item(results, 0)
    assert String.length(ok.name) == 100

    assert {1, :error, {:validation, errs}} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert Map.has_key?(errs, "name")
    assert Catalog.count() == 1
  end