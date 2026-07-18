  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_size, 10)
    min = Keyword.get(opts, :min_size, 0)
    create = Keyword.get(opts, :create, fn -> make_ref() end)

    cond do
      not (is_integer(max) and max >= 0) ->
        {:stop, {:invalid_option, :max_size}}

      not (is_integer(min) and min >= 0) ->
        {:stop, {:invalid_option, :min_size}}

      min > max ->
        {:stop, {:invalid_option, :min_size_gt_max_size}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      true ->
        available = for _ <- 1..min//1, do: create.()

        state = %__MODULE__{
          available: available,
          in_use: %{},
          waiters: :queue.new(),
          total: min,
          max: max,
          min: min,
          create: create
        }

        {:ok, state}
    end
  end