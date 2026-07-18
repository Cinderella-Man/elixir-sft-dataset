  test "forward/reverse consistency holds across a mixed sequence", %{bm: bm} do
    ops = [
      {:put, :a, 1},
      {:put, :a, 2},
      {:put, :b, 1},
      {:put, :c, 3},
      {:delete, :a, 1},
      {:put, :b, 2},
      {:delete_value, 3},
      {:put, :c, 2},
      {:delete_key, :a},
      {:put, :d, 1}
    ]

    Enum.each(ops, fn
      {:put, k, v} -> assert :ok = BiMultiMap.put(bm, k, v)
      {:delete, k, v} -> assert :ok = BiMultiMap.delete(bm, k, v)
      {:delete_key, k} -> assert :ok = BiMultiMap.delete_key(bm, k)
      {:delete_value, v} -> assert :ok = BiMultiMap.delete_value(bm, v)
    end)

    keys = [:a, :b, :c, :d]
    values = [1, 2, 3]

    # Every forward association must be mirrored in the reverse index.
    for k <- keys, v <- BiMultiMap.get_by_key(bm, k) do
      assert MapSet.member?(BiMultiMap.get_by_value(bm, v), k)
      assert BiMultiMap.member?(bm, k, v)
    end

    # Every reverse association must be mirrored in the forward index.
    for v <- values, k <- BiMultiMap.get_by_value(bm, v) do
      assert MapSet.member?(BiMultiMap.get_by_key(bm, k), v)
      assert BiMultiMap.member?(bm, k, v)
    end
  end