  defp size_reached?(%{batch_size: :infinity}), do: false
  defp size_reached?(%{count: count, batch_size: size}), do: count >= size