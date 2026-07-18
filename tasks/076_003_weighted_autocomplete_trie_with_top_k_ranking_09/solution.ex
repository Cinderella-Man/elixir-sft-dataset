  @doc "Returns `true` if the exact `word` has a positive weight."
  @spec member?(t, String.t()) :: boolean
  def member?(%__MODULE__{} = trie, word) when is_binary(word), do: weight(trie, word) > 0