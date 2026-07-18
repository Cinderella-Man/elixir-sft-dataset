  @spec mask_emails(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_emails(string) do
    count = length(Regex.scan(@email_regex, string))

    scrubbed =
      Regex.replace(@email_regex, string, fn _full, local, domain ->
        "#{String.first(local)}***@#{domain}"
      end)

    {scrubbed, count}
  end