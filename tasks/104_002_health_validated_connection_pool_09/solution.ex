  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_size, 10)
    min = Keyword.get(opts, :min_size, 0)
    create = Keyword.get(opts, :create, fn -> make_ref() end)
    validate = Keyword.get(opts, :validate, fn _ -> true end)
    destroy = Keyword.get(opts, :destroy, fn _ -> :ok end)

    cond do
      not (is_integer(max) and max >= 0) ->
        {:stop, {:invalid_option, :max_size}}

      not (is_integer(min) and min >= 0) ->
        {:stop, {:invalid_option, :min_size}}

      min > max ->
        {:stop, {:invalid_option, :min_size_gt_max_size}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      not is_function(validate, 1) ->
        {:stop, {:invalid_option, :validate}}

      not is_function(destroy, 1) ->
        {:stop, {:invalid_option, :destroy}}

      true ->
        available = for _ <- 1..min//1, do: create.()

        {:ok,
         %__MODULE__{
           available: available,
           total: min,
           max: max,
           min: min,
           create: create,
           validate: validate,
           destroy: destroy
         }}
    end
  end