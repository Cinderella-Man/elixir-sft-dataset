  defp invalid_sort?(%{"sort" => s}), do: s not in @allowed_sort
  defp invalid_sort?(_), do: false