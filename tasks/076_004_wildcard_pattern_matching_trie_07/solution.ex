  @doc "Inserts `word` into the trie. Returns the updated trie."
  @spec insert(t, String.t()) :: t
  def insert(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if exact?(root, chars) do
      trie
    else
      %__MODULE__{root: do_insert(root, chars), size: size + 1}
    end
  end