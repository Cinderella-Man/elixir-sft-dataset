  @doc "Returns the accumulated weight of `word`, or 0 if absent."
  @spec weight(t, String.t()) :: non_neg_integer
  def weight(%__MODULE__{root: root}, word) when is_binary(word) do
    case descend(root, String.graphemes(word)) do
      nil -> 0
      node -> node.weight
    end
  end