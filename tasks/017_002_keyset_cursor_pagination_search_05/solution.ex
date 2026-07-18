  defp validate_sort(%{"sort" => s}) when s not in @allowed_sort,
    do: {:error, :invalid_sort_field}

  defp validate_sort(_), do: :ok