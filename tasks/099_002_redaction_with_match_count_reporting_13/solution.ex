  @spec mask_credit_cards(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_credit_cards(string) do
    count = length(Regex.scan(@cc_regex, string))
    scrubbed = Regex.replace(@cc_regex, string, &mask_cc_match/1)
    {scrubbed, count}
  end