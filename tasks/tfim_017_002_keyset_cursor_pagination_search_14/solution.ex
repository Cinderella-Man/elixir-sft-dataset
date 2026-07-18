  test "cursor carrying a wrongly typed payload is rejected instead of silently slicing" do
    forged =
      {"price", "not-a-price", 5}
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    assert {:error, :invalid_cursor} =
             KeysetSearch.search(products(), %{"sort" => "price", "cursor" => forged})
  end