  @doc """
  Returns a sorted list of every word that starts with `prefix`.

  The prefix may end in the middle of a compressed edge.
  """
  @spec search(t, String.t()) :: [String.t()]
  def search(%__MODULE__{root: root}, prefix) when is_binary(prefix) do
    case locate(root, prefix, "") do
      :nomatch -> []
      {node, path} -> collect(node, path) |> Enum.sort()
    end
  end