  test "bijection invariant holds across a mixed operation sequence", %{bm: bm} do
    ops = [
      {:put, :a, 1},
      {:put, :b, 2},
      {:put, :c, 3},
      {:put, :a, 2},
      {:put, :d, 3},
      {:delete, :b},
      {:put, :e, 1},
      {:put, :a, 5},
      {:delete, :z},
      {:put, :f, 5}
    ]

    keys = [:a, :b, :c, :d, :e, :f, :z]
    values = [1, 2, 3, 4, 5, 6]

    Enum.each(ops, fn
      {:put, k, v} -> assert :ok = BiMap.put(bm, k, v)
      {:delete, k} -> assert :ok = BiMap.delete(bm, k)
    end)

    # Forward -> reverse consistency for every key that survived.
    for k <- keys do
      case BiMap.get_by_key(bm, k) do
        {:ok, v} -> assert {:ok, ^k} = BiMap.get_by_value(bm, v)
        :error -> :ok
      end
    end

    # Reverse -> forward consistency for every value that survived.
    for v <- values do
      case BiMap.get_by_value(bm, v) do
        {:ok, k} -> assert {:ok, ^v} = BiMap.get_by_key(bm, k)
        :error -> :ok
      end
    end

    # No value maps to more than one key: collect surviving (value -> key)
    # pairs and ensure keys are unique across distinct values.
    surviving =
      for v <- values, match?({:ok, _}, BiMap.get_by_value(bm, v)) do
        {:ok, k} = BiMap.get_by_value(bm, v)
        {v, k}
      end

    surviving_keys = Enum.map(surviving, fn {_v, k} -> k end)
    assert length(surviving_keys) == length(Enum.uniq(surviving_keys))
  end