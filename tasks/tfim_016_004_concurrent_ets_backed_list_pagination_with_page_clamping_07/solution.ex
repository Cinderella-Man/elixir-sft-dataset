  test "clamps page_size and coerces bad page values" do
    table = EtsCatalog.new() |> seed(1..150)

    %{meta: meta} = EtsCatalog.list(table, %{"page_size" => "500", "page" => "-3"})
    assert meta.page_size == 100
    assert meta.requested_page == 1
    assert meta.current_page == 1
    assert meta.total_pages == 2
  end