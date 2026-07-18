  @doc """
  Removes `word` from the trie. Returns the updated trie.

  Only the end-of-word marker is cleared; shared prefix nodes that are still
  needed by other words are left intact. Orphaned branch nodes are pruned.

  Deleting a word that isn't present is a no-op.
  """
  @spec delete(t, String.t()) :: t
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if word_exists?(root, chars) do
      %__MODULE__{root: do_delete(root, chars), size: size - 1}
    else
      trie
    end
  end