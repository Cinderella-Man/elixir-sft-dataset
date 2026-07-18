  @doc "Creates a promo code from `attrs`. Returns `{:ok, code}` or `{:error, reason}`."
  @spec create(map()) :: {:ok, map()} | {:error, atom()}
  def create(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:create, attrs})