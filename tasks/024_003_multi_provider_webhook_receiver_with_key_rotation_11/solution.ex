  @doc """
  Return `:ok` if `verify/4` succeeds for ANY secret in the `secrets` list,
  otherwise `:error`. Useful for accepting a rotatable set of secrets.
  """
  @spec verify_any(term(), term(), [binary()], binary()) :: :ok | :error
  def verify_any(payload, signature, secrets, prefix \\ "") when is_list(secrets) do
    if Enum.any?(secrets, fn s -> verify(payload, signature, s, prefix) == :ok end) do
      :ok
    else
      :error
    end
  end