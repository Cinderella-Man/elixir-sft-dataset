  defp include_archived?(opts) when is_list(opts) do
    Keyword.get(opts, :include_archived, false) == true
  end