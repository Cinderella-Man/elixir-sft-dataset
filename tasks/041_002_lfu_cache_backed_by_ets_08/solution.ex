  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    # A missing :max_size fails like an invalid one — ArgumentError, not the
    # KeyError a fetch! would raise (the contract reserves that for :name).
    max_size =
      case Keyword.fetch(opts, :max_size) do
        {:ok, value} -> value
        :error -> raise ArgumentError, ":max_size is required"
      end

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    data_table =
      :ets.new(data_table_name(name), [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    order_table =
      :ets.new(order_table_name(name), [
        :ordered_set,
        :protected,
        :named_table
      ])

    state = %{
      data_table: data_table,
      order_table: order_table,
      max_size: max_size,
      counter: 0
    }

    {:ok, state}
  end