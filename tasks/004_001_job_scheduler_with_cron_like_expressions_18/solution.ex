  defp parse_int(str) do
    case Integer.parse(str) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end