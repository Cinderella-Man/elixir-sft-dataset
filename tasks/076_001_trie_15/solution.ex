  @doc """
  Returns a sorted list of every word that starts with `prefix`.

  If `prefix` itself was inserted as a word it is included in the result.
  """
  @spec search(t, String.t()) :: [String.t()]
  def search(%__MODULE__{root: root}, prefix) when is_binary(prefix) do
    chars = String.graphemes(prefix)

    case descend(root, chars) do
      nil -> []
      node -> collect(node, prefix) |> Enum.sort()
    end
  end