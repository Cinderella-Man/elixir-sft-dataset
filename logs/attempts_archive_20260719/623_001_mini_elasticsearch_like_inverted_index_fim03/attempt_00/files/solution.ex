  def stem(word) do
    word
    |> strip_suffix("tion", "t")
    |> strip_suffix("ment", "")
    |> strip_suffix("ing", "")
    |> strip_suffix("er", "")
    |> strip_suffix("ly", "")
    |> strip_suffix("ed", "")
    |> strip_suffix("s", "")
    |> dedup_trailing_consonant()
  end