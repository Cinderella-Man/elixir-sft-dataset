  @doc """
  Parses an `otpauth://totp/...` provisioning URI into a validated configuration map.

  Returns `{:ok, config}` on success, or `{:error, reason}` where `reason` is one of
  `:invalid_scheme`, `:unsupported_type`, `:missing_label`, `:missing_secret`,
  `:invalid_secret`, `:issuer_mismatch`, `:unsupported_algorithm`, `:invalid_digits` or
  `:invalid_period`.
  """
  @spec parse(term()) :: {:ok, t()} | {:error, atom()}
  def parse(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    with :ok <- validate_scheme(parsed.scheme),
         :ok <- validate_type(parsed.host),
         {:ok, label_issuer, account} <- parse_label(parsed.path) do
      params = URI.decode_query(parsed.query || "")

      with {:ok, secret} <- parse_secret(params),
           {:ok, issuer} <- parse_issuer(label_issuer, params),
           {:ok, algorithm} <- parse_algorithm(params),
           {:ok, digits} <- parse_digits(params),
           {:ok, period} <- parse_period(params) do
        {:ok,
         %{
           issuer: issuer,
           account: account,
           secret: secret,
           algorithm: algorithm,
           digits: digits,
           period: period
         }}
      end
    end
  end

  def parse(_uri), do: {:error, :invalid_scheme}