  @spec valid_bucket_name?(term()) :: boolean()
  defp valid_bucket_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@name_regex, name)
  end

  defp valid_bucket_name?(_name), do: false