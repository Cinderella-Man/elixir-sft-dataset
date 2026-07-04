  test "middle page returns the correct window" do
    table = EtsCatalog.new() |> seed(1..12)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "2", "page_size" => "5"})
    assert Enum.map(data, & &1.id) == [6, 7, 8, 9, 10]
    assert meta.current_page == 2
  end