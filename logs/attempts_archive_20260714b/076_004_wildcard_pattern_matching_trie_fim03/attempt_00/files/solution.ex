  defp do_matches?(%{terminal: terminal}, []), do: terminal

  defp do_matches?(%{children: children}, [@wildcard | rest]) do
    Enum.any?(children, fn {_char, child} -> do_matches?(child, rest) end)
  end

  defp do_matches?(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> do_matches?(child, rest)
      :error -> false
    end
  end