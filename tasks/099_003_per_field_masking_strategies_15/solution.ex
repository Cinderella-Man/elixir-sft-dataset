  @spec lookup(t(), term()) :: {:ok, strategy()} | :error
  defp lookup(%__MODULE__{policies: policies}, key) do
    case norm_key(key) do
      {:ok, normalized} -> Map.fetch(policies, normalized)
      :error -> :error
    end
  end