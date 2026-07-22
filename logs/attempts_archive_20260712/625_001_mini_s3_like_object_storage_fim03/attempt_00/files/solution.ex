  defp validate_bucket_name(name) when is_binary(name) and byte_size(name) > 0 do
    if Regex.match?(@bucket_name_re, name), do: :ok, else: {:error, :invalid_name}
  end

  defp validate_bucket_name(_), do: {:error, :invalid_name}