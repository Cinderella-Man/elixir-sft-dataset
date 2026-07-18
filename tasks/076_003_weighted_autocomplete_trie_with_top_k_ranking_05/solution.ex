  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}