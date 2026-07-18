  @spec mask_credit_cards(String.t()) :: String.t()
  defp mask_credit_cards(str) do
    Regex.replace(@cc_regex, str, fn match -> mask_cc(match) end)
  end