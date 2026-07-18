  test "new returns a fresh table that is independent of earlier ones" do
    first = EtsCatalog.new() |> seed(1..3)
    second = EtsCatalog.new()

    assert EtsCatalog.count(first) == 3
    assert EtsCatalog.count(second) == 0
    assert %{data: [], meta: %{total_count: 0, total_pages: 0}} = EtsCatalog.list(second)

    EtsCatalog.insert(second, %{id: 99, name: "only second"})
    assert EtsCatalog.count(first) == 3
    assert EtsCatalog.count(second) == 1
  end