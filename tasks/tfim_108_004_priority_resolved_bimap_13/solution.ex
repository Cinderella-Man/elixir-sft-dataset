  test "bijection holds across a mixed accept/reject sequence", %{bm: bm} do
    ops = [
      {:a, 1, 10},
      {:b, 2, 10},
      {:c, 3, 5},
      {:a, 2, 3},
      {:a, 2, 20},
      {:d, 3, 1},
      {:e, 3, 9},
      {:b, 1, 25}
    ]

    Enum.each(ops, fn {k, v, p} -> PriorityBiMap.put(bm, k, v, p) end)

    keys = [:a, :b, :c, :d, :e]
    values = [1, 2, 3]

    for k <- keys do
      case PriorityBiMap.get_by_key(bm, k) do
        {:ok, v} -> assert {:ok, ^k} = PriorityBiMap.get_by_value(bm, v)
        :error -> :ok
      end
    end

    for v <- values do
      case PriorityBiMap.get_by_value(bm, v) do
        {:ok, k} -> assert {:ok, ^v} = PriorityBiMap.get_by_key(bm, k)
        :error -> :ok
      end
    end
  end