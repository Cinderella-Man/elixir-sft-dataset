  @spec boost(any(), map()) :: number()
  defp boost(field, boosts), do: Map.get(boosts, field, 1)