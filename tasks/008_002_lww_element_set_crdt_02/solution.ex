  @spec element_present?(lww_state(), element()) :: boolean()
  defp element_present?(%{adds: adds, removes: removes}, element) do
    case Map.fetch(adds, element) do
      {:ok, add_ts} ->
        remove_ts = Map.get(removes, element, 0)
        add_ts > remove_ts

      :error ->
        false
    end
  end