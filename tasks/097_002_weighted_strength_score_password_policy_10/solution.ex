  defp strength_reason(score, %{min_score: min}) do
    if score < min, do: :insufficient_strength, else: nil
  end