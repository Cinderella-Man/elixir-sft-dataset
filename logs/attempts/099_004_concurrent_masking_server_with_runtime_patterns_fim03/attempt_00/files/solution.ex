  # Walks a list of `{key, value}` pairs shared by maps and keyword lists.
  defp walk_pairs(state, pairs, acc) do
    Enum.map_reduce(pairs, acc, fn {key, value}, {ks, pa} = ac ->
      if sensitive?(state, key) do
        {{key, @masked}, {ks + 1, pa}}
      else
        {masked_value, ac2} = walk(state, value, ac)
        {{key, masked_value}, ac2}
      end
    end)
  end