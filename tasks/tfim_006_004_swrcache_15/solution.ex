  test "re-put overwrites the loader used for revalidation", %{c: c} do
    parent = self()

    loader_a = fn ->
      send(parent, :loader_a)
      :va
    end

    loader_b = fn ->
      send(parent, :loader_b)
      :vb
    end

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, loader_a)
    # Overwrite the same key — the new loader must replace the old one.
    :ok = SwrCache.put(c, :a, :v2, 1_000, 2_000, loader_b)

    Clock.advance(1_000)
    assert {:ok, :v2, :stale} = SwrCache.get(c, :a)

    assert_receive :loader_b, 500
    refute_receive :loader_a, 50
  end