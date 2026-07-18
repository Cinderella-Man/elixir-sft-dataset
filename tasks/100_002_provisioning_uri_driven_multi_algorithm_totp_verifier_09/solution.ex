  @spec validate_type(String.t() | nil) :: :ok | {:error, :unsupported_type}
  defp validate_type(host) when is_binary(host) do
    if String.downcase(host) == "totp", do: :ok, else: {:error, :unsupported_type}
  end

  defp validate_type(_host), do: {:error, :unsupported_type}