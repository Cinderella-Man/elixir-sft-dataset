  defp score_doc(doc, query_terms, postings, n, avgdl, k1, b, boosts) do
    wlen = weighted_length(doc, boosts)
    ratio = if avgdl == +0.0, do: +0.0, else: wlen / avgdl

    Enum.reduce(query_terms, +0.0, fn t, acc ->
      f = term_frequency(doc, t, boosts)

      if f == +0.0 do
        acc
      else
        df = postings |> Map.get(t, MapSet.new()) |> MapSet.size()
        idf = :math.log(1 + (n - df + 0.5) / (df + 0.5))
        denom = f + k1 * (1 - b + b * ratio)
        acc + idf * (f * (k1 + 1)) / denom
      end
    end)
  end