  @doc "Removes the exact `word`. Deleting an absent word is a no-op."
  @spec delete(t, String.t()) :: t
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if exact?(root, chars) do
      %__MODULE__{root: do_delete(root, chars), size: size - 1}
    else
      trie
    end
  end