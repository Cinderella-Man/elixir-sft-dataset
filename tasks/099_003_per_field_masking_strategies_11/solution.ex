  @spec mask_emails(String.t()) :: String.t()
  defp mask_emails(str) do
    Regex.replace(@email_regex, str, fn _full, local, domain ->
      String.first(local) <> "***@" <> domain
    end)
  end