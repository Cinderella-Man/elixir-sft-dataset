  @doc """
  Builds an `otpauth://totp/` provisioning URI for authenticator apps.

  The label is `issuer:account_name` (both URI-encoded); query parameters
  include `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, `period=30`.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t()) :: String.t()
  def provisioning_uri(secret, issuer, account_name) do
    label =
      URI.encode(issuer, &URI.char_unreserved?/1) <>
        ":" <> URI.encode(account_name, &URI.char_unreserved?/1)

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", "SHA1"},
        {"digits", Integer.to_string(@digits)},
        {"period", Integer.to_string(@period)}
      ])

    "otpauth://totp/" <> label <> "?" <> query
  end