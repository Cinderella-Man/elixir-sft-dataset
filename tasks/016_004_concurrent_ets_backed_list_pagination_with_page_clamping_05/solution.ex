  @doc """
  Create and return a fresh `:ordered_set`, `:public` ETS table backing the
  catalog. Items are keyed by their integer id and other processes may insert
  concurrently.
  """
  @spec new() :: :ets.tid()
  def new do
    :ets.new(:ets_catalog, [:ordered_set, :public])
  end