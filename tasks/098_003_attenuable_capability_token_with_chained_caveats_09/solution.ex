  defp take_caveats(0, rest, acc), do: {:ok, Enum.reverse(acc), rest}

  defp take_caveats(count, <<len::16, caveat::binary-size(len), rest::binary>>, acc)
       when count > 0 do
    take_caveats(count - 1, rest, [caveat | acc])
  end

  defp take_caveats(_count, _rest, _acc), do: :error