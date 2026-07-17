  defp parse_page_size(%{"page_size" => raw}) do
    case parse_paging_int(raw) do
      {:ok, n} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_), do: @default_page_size