  defp parse_page(%{"page" => raw}) do
    case parse_paging_int(raw) do
      {:ok, n} when n >= 1 -> n
      _ -> @default_page
    end
  end

  defp parse_page(_), do: @default_page