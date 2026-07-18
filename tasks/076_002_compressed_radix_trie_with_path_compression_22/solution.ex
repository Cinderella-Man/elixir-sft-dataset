  @doc """
  Removes `word`. Restores the compression invariant by re-merging any node
  left with a single child. Deleting an absent word is a no-op.
  """
  @spec delete(t, String.t()) :: t
  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    case do_delete(root, word) do
      :notfound -> trie
      {new_root, :ok} -> %__MODULE__{root: new_root, size: size - 1}
    end
  end