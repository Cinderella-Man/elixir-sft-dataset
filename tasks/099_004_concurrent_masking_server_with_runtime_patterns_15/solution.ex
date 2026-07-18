  # Keeps only the first character of the local part.
  defp mask_email(match) do
    [local, domain] = String.split(match, "@", parts: 2)
    String.first(local) <> "***@" <> domain
  end