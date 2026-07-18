  defp mask_ssns(string) do
    Regex.replace(@ssn_regex, string, "***-**-****")
  end