  @doc """
  Builds an opaque masker from `policies`.

  `policies` is a map or keyword list mapping a key (atom and/or string) to a
  masking strategy (`:redact`, `:last4`, or `:hash`). Keys are normalized so
  that comparison at mask time is case-insensitive for both atom and string
  keys.

  Raises `ArgumentError` for unsupported key types or unknown strategies.
  """
  @spec new(map() | keyword()) :: t()
  def new(policies) do
    normalized =
      Enum.into(policies, %{}, fn {key, strategy} ->
        {normalize_policy_key(key), validate_strategy(strategy)}
      end)

    %__MODULE__{policies: normalized}
  end