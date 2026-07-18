  # Structs are returned unchanged.
  defp walk(_state, term, acc) when is_struct(term), do: {term, acc}

  defp walk(state, term, acc) when is_map(term) do
    {pairs, acc2} = walk_pairs(state, Map.to_list(term), acc)
    {Map.new(pairs), acc2}
  end

  defp walk(state, term, acc) when is_list(term) do
    if term != [] and Keyword.keyword?(term) do
      walk_pairs(state, term, acc)
    else
      Enum.map_reduce(term, acc, fn element, ac -> walk(state, element, ac) end)
    end
  end

  defp walk(state, term, {ks, pa}) when is_binary(term) do
    {scrubbed, count} = scrub(state, term)
    {scrubbed, {ks, pa + count}}
  end

  defp walk(_state, term, acc), do: {term, acc}