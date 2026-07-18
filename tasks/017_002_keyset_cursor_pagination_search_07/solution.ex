  defp order(params) do
    case Map.get(params, "order") do
      "desc" -> :desc
      _ -> :asc
    end
  end