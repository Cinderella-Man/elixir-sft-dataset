  @spec validate_strategy(term()) :: strategy()
  defp validate_strategy(strategy) when strategy in [:redact, :last4, :hash] do
    strategy
  end

  defp validate_strategy(strategy) do
    raise ArgumentError, "invalid masking strategy: #{inspect(strategy)}"
  end