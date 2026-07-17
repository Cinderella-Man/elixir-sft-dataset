  test "omitted page_size serves twenty items per page by default" do
    table = EtsCatalog.new() |> seed(1..25)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "1"})
    assert meta.page_size == 20
    assert length(data) == 20
    assert Enum.map(data, & &1.id) == Enum.to_list(1..20)
    assert meta.total_pages == 2
  end