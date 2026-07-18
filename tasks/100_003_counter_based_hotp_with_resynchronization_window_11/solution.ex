  @doc """
  Builds an `otpauth://hotp/` provisioning URI for authenticator apps.

  The label is `issuer:account_name` with both parts URI-encoded. The query
  carries `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and `counter`, all
  properly URI-encoded.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t(), integer()) :: String.t()
  def provisioning_uri(secret, issuer, account_name, counter) do
    label = encode_component(issuer) <> ":" <> encode_component(account_name)

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", "SHA1"},
        {"digits", Integer.to_string(@digits)},
        {"counter", Integer.to_string(counter)}
      ])

    "otpauth://hotp/" <> label <> "?" <> query
  end