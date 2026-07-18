  @spec element_present?(tp_state(), element()) :: boolean()
  defp element_present?(%{added: added, removed: removed}, element) do
    MapSet.member?(added, element) and not MapSet.member?(removed, element)
  end