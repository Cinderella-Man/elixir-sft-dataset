  def start_link(opts) do
    name = Keyword.get(opts, :name)
    max = Keyword.get(opts, :max_concurrency, 4)

    unless is_integer(max) and max > 0 do
      raise ArgumentError, ":max_concurrency must be a positive integer"
    end

    GenServer.start_link(__MODULE__, max, name: name)
  end