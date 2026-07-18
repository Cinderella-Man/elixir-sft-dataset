  @doc "Inserts `word` into the trie. Returns the updated trie."
  @spec insert(t, String.t()) :: t
  def insert(%__MODULE__{root: root, size: size}, word) when is_binary(word) do
    {new_root, added} = do_insert(root, word)
    %__MODULE__{root: new_root, size: size + added}
  end