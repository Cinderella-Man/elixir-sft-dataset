  @spec mask_ssns(String.t()) :: {String.t(), non_neg_integer()}
  defp mask_ssns(string) do
    count = length(Regex.scan(@ssn_regex, string))
    {Regex.replace(@ssn_regex, string, "***-**-****"), count}
  end