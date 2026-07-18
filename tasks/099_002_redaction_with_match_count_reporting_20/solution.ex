  @doc """
  Builds an opaque redactor configuration from a list of sensitive keys.

  `sensitive_keys` may contain atoms and/or strings. Comparisons performed at
  redaction time are case-insensitive and match both atom and string keys.
  """
  @spec new([atom() | String.t()]) :: t()
  def new(sensitive_keys) when is_list(sensitive_keys) do
    set =
      sensitive_keys
      |> Enum.map(&normalize_key/1)
      |> MapSet.new()

    %__MODULE__{keys: set}
  end