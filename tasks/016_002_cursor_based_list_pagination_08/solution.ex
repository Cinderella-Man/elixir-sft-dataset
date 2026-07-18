  # Only a fully numeric value counts: "12abc" has trailing junk and is rejected,
  # falling back to the default limit rather than silently reading as 12.
  defp parse_limit(%{"limit" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n >= 1 -> min(n, @max_limit)
      _ -> @default_limit
    end
  end

  defp parse_limit(_), do: @default_limit