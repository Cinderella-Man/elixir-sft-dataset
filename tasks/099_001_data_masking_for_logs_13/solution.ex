  defp digit?(<<c>>) when c in ?0..?9, do: true
  defp digit?(_), do: false