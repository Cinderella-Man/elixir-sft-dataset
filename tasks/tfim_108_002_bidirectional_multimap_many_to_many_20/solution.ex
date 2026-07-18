  test "randomised operation stream never breaks the invariant", %{bm: bm} do
    keys = [:k1, :k2, :k3, :k4]
    values = [1, 2, 3, 4]
    :rand.seed(:exsss, {101, 202, 303})

    for _ <- 1..300 do
      k = Enum.random(keys)
      v = Enum.random(values)

      case Enum.random([:put, :put, :put, :delete, :delete_key, :delete_value]) do
        :put -> assert :ok = BiMultiMap.put(bm, k, v)
        :delete -> assert :ok = BiMultiMap.delete(bm, k, v)
        :delete_key -> assert :ok = BiMultiMap.delete_key(bm, k)
        :delete_value -> assert :ok = BiMultiMap.delete_value(bm, v)
      end
    end

    for k <- keys, v <- values do
      in_forward = MapSet.member?(BiMultiMap.get_by_key(bm, k), v)
      in_reverse = MapSet.member?(BiMultiMap.get_by_value(bm, v), k)

      assert in_forward == in_reverse
      assert BiMultiMap.member?(bm, k, v) == in_forward
    end
  end