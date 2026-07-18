  # Only strip if the remaining root has at least 2 characters.
  defp strip_suffix(word, suffix, replacement) do
    suffix_len = byte_size(suffix)
    root_len = byte_size(word) - suffix_len

    if root_len >= 2 and String.ends_with?(word, suffix) do
      String.slice(word, 0, root_len) <> replacement
    else
      word
    end
  end