  defp do_common([x | xs], [x | ys], acc), do: do_common(xs, ys, [x | acc])
  defp do_common(_, _, acc), do: acc |> Enum.reverse() |> Enum.join()