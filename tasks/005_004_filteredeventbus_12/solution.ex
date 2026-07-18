  defp valid_filter?(filter) when is_list(filter) do
    Enum.all?(filter, &valid_clause?/1)
  end