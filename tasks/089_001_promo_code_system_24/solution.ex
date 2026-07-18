  @doc """
  Creates a new promo code.

  Returns `{:ok, code}` on success or `{:error, reason}` where `reason` is one
  of `:invalid_type` or `:already_exists`.
  """
  @spec create(map()) :: {:ok, map()} | {:error, atom()}
  def create(attrs) when is_map(attrs) do
    GenServer.call(server(), {:create, attrs})
  end