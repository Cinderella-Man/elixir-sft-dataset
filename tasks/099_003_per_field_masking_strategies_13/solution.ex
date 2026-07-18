  @spec mask_ssns(String.t()) :: String.t()
  defp mask_ssns(str) do
    Regex.replace(@ssn_regex, str, "***-**-****")
  end