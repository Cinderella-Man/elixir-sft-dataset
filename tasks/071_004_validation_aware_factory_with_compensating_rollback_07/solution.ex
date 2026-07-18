  @doc "Like `insert/2` but returns the struct on success and raises otherwise."
  @spec insert!(factory_name()) :: struct()
  def insert!(name), do: insert!(name, [])

  @doc "Like `insert/2` but returns the struct on success and raises otherwise."
  @spec insert!(factory_name(), overrides()) :: struct()
  def insert!(name, overrides) do
    case insert(name, overrides) do
      {:ok, struct} ->
        struct

      {:error, reason} ->
        raise ArgumentError,
              "insert!/2 failed for #{inspect(name)}: #{inspect(reason)}"
    end
  end