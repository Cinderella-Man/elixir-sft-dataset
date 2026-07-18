  @doc """
  Inserts `word` with `weight` (default 1). Re-inserting a word adds to its
  accumulated weight. Returns the updated trie.
  """
  @spec insert(t, String.t(), pos_integer) :: t
  def insert(%__MODULE__{root: root, size: size}, word, weight \\ 1)
      when is_binary(word) and is_integer(weight) and weight > 0 do
    {new_root, delta} = do_insert(root, String.graphemes(word), weight)
    %__MODULE__{root: new_root, size: size + delta}
  end