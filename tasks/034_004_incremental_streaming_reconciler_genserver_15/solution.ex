  @spec opposite(:left | :right) :: :left | :right
  defp opposite(:left), do: :right
  defp opposite(:right), do: :left