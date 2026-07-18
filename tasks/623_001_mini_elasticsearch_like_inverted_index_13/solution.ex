  defp dedup_trailing_consonant(word) when byte_size(word) >= 3 do
    len = byte_size(word)
    last = String.at(word, len - 1)
    second_last = String.at(word, len - 2)

    if last == second_last and last not in ~w(a e i o u),
      do: String.slice(word, 0, len - 1),
      else: word
  end

  defp dedup_trailing_consonant(word), do: word