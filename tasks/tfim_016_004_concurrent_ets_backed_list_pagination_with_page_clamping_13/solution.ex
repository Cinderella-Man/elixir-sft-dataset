  test "non-numeric page falls back to page one for requested and current" do
    table = EtsCatalog.new() |> seed(1..25)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "oops", "page_size" => "10"})
    assert meta.requested_page == 1
    assert meta.current_page == 1
    assert Enum.map(data, & &1.id) == Enum.to_list(1..10)
  end