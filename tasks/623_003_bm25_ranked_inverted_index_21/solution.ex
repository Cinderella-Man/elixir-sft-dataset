  @spec weighted_length(document(), map()) :: float()
  defp weighted_length(doc, boosts) do
    Enum.reduce(doc.lengths, +0.0, fn {field, len}, acc ->
      acc + len * boost(field, boosts)
    end)
  end