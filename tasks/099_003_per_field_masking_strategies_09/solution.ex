  @spec apply_strategy(strategy(), term()) :: term()
  defp apply_strategy(:redact, _value), do: "[MASKED]"
  defp apply_strategy(:last4, value), do: last4(value)
  defp apply_strategy(:hash, value), do: hash(value)