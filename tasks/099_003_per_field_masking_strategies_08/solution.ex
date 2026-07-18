  @spec mask_pair(t(), term(), term()) :: {term(), term()}
  defp mask_pair(masker, key, value) do
    case lookup(masker, key) do
      {:ok, strategy} -> {key, apply_strategy(strategy, value)}
      :error -> {key, do_mask(masker, value)}
    end
  end