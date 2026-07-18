  test "equal relevance scores with identical names fall back to id ascending" do
    catalog = [
      %{id: 7, name: "Alpha Kit", description: "kit", category: "c", price_cents: 100},
      %{id: 3, name: "Alpha Kit", description: "kit", category: "c", price_cents: 200},
      %{id: 9, name: "Alpha Box", description: "kit", category: "c", price_cents: 300}
    ]

    assert {:ok, %{data: data}} = Ranked.search(catalog, %{"q" => "alpha"})

    assert Enum.map(data, & &1.score) == [3, 3, 3]
    assert ids(data) == [9, 3, 7]
  end