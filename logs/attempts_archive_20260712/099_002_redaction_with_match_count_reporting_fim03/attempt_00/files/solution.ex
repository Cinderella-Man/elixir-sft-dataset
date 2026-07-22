  @spec scrub_string(String.t()) :: {String.t(), report()}
  defp scrub_string(string) do
    {s1, cards} = mask_credit_cards(string)
    {s2, ssns} = mask_ssns(s1)
    {s3, emails} = mask_emails(s2)

    {s3, %{keys_masked: 0, credit_cards: cards, emails: emails, ssns: ssns}}
  end