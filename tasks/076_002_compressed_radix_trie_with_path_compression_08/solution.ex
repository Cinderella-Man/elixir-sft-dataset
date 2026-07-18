  @doc "Returns `true` only if the exact `word` was inserted."
  @spec member?(t, String.t()) :: boolean
  def member?(%__MODULE__{root: root}, word) when is_binary(word), do: do_member(root, word)