  @doc "Returns a sorted list of every word in the trie."
  @spec words(t) :: [String.t()]
  def words(%__MODULE__{root: root}) do
    collect(root, "") |> Enum.sort()
  end