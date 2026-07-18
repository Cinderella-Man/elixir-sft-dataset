  test "validation errors_map is keyed by string field with a list of message strings" do
    assert {:error, results} = Catalog.bulk_create([%{"name" => ""}])
    assert {0, :error, {:validation, errs}} = hd(results)

    assert errs == %{"name" => ["can't be blank"]}
    assert Enum.all?(Map.keys(errs), &is_binary/1)
    assert Enum.all?(errs["name"], &is_binary/1)
  end