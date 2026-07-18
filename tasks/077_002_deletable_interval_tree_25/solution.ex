  defp do_enclosing(nil, _point, acc), do: acc
  defp do_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp do_enclosing(%{interval: {s, f} = iv, left: left, right: right}, point, acc) do
    acc = if s <= point and point <= f, do: [iv | acc], else: acc
    acc = do_enclosing(left, point, acc)

    if s <= point do
      do_enclosing(right, point, acc)
    else
      acc
    end
  end