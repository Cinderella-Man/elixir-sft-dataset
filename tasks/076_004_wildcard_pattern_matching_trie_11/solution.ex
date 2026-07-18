  @doc "Returns `true` if any stored word matches `pattern` (`.` = any char)."
  @spec matches?(t, String.t()) :: boolean
  def matches?(%__MODULE__{root: root}, pattern) when is_binary(pattern) do
    do_matches?(root, String.graphemes(pattern))
  end