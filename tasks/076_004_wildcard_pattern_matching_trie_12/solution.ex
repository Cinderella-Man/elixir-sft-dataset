  @doc "Returns a sorted list of every stored word matching `pattern`."
  @spec matching(t, String.t()) :: [String.t()]
  def matching(%__MODULE__{root: root}, pattern) when is_binary(pattern) do
    root |> do_matching(String.graphemes(pattern), "") |> Enum.sort()
  end