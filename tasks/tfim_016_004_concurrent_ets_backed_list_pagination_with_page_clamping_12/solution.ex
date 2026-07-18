  test "non-numeric and below-range page_size values fall back to twenty" do
    table = EtsCatalog.new() |> seed(1..25)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page_size" => "abc"})
    assert meta.page_size == 20
    assert length(data) == 20

    %{meta: zero_meta} = EtsCatalog.list(table, %{"page_size" => "0"})
    assert zero_meta.page_size == 20
    assert zero_meta.total_pages == 2
  end