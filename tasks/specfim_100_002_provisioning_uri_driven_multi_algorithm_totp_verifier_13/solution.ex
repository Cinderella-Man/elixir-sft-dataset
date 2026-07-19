  @spec parse_issuer(String.t() | nil, map()) ::
          {:ok, String.t() | nil} | {:error, :issuer_mismatch}