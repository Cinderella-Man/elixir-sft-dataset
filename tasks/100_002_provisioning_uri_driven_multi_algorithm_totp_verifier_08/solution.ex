  @spec validate_scheme(String.t() | nil) :: :ok | {:error, :invalid_scheme}
  defp validate_scheme(scheme) when is_binary(scheme) do
    if String.downcase(scheme) == "otpauth", do: :ok, else: {:error, :invalid_scheme}
  end

  defp validate_scheme(_scheme), do: {:error, :invalid_scheme}