  @spec sensitive?(t(), term()) :: boolean()
  defp sensitive?(redactor, key) do
    case key_string(key) do
      nil -> false
      norm -> MapSet.member?(redactor.keys, norm)
    end
  end