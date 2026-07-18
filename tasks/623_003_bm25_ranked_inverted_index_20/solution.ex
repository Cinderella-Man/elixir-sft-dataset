  @spec term_frequency(document(), String.t(), map()) :: float()
  defp term_frequency(doc, term, boosts) do
    Enum.reduce(doc.terms, +0.0, fn {field, tmap}, acc ->
      acc + Map.get(tmap, term, 0) * boost(field, boosts)
    end)
  end