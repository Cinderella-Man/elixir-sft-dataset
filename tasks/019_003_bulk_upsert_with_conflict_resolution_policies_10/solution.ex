  defp put_name_error(errors, attrs) do
    case attrs["name"] do
      n when is_binary(n) and byte_size(n) > 0 ->
        if String.length(n) <= 100,
          do: errors,
          else: Map.put(errors, "name", ["should be at most 100 character(s)"])

      _ ->
        Map.put(errors, "name", ["can't be blank"])
    end
  end