  test "concurrent misses call the loader at most once", %{cl: cl} do
    loader = fn -> Process.sleep(20); Store.loaded(:v) end

    results =
      for _ <- 1..25 do
        Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", loader) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == {:ok, :v}))
    assert Store.counts().loads == 1
  end