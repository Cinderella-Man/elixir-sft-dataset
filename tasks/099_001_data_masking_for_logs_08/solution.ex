  defp mask_credit_cards(string) do
    Regex.replace(@cc_regex, string, &mask_cc_match/1)
  end