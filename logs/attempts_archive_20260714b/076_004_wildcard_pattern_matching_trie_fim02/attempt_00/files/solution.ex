  defp do_matching(%{terminal: terminal}, [], acc) do
    if terminal, do: [acc], else: []
  end

  defp do_matching(%{children: children}, [@wildcard | rest], acc) do
    Enum.flat_map(children, fn {char, child} -> do_matching(child, rest, acc <> char) end)
  end

  defp do_matching(%{children: children}, [char | rest], acc) do
    case Map.fetch(children, char) do
      {:ok, child} -> do_matching(child, rest, acc <> char)
      :error -> []
    end
  end