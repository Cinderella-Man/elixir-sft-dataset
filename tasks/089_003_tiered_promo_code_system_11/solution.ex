  defp ascending?([]), do: true
  defp ascending?([_]), do: true
  defp ascending?([a, b | rest]), do: a < b and ascending?([b | rest])