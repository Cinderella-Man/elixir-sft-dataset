  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_size, 10)
    min = Keyword.get(opts, :min_size, 0)
    max_uses = Keyword.get(opts, :max_uses, :infinity)
    create = Keyword.get(opts, :create, fn -> make_ref() end)
    destroy = Keyword.get(opts, :destroy, fn _ -> :ok end)

    cond do
      not (is_integer(max) and max >= 0) ->
        {:stop, {:invalid_option, :max_size}}

      not (is_integer(min) and min >= 0) ->
        {:stop, {:invalid_option, :min_size}}

      min > max ->
        {:stop, {:invalid_option, :min_size_gt_max_size}}

      not (max_uses == :infinity or (is_integer(max_uses) and max_uses > 0)) ->
        {:stop, {:invalid_option, :max_uses}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      not is_function(destroy, 1) ->
        {:stop, {:invalid_option, :destroy}}

      true ->
        available = for _ <- 1..min//1, do: create.()
        uses = Map.new(available, fn c -> {c, 0} end)

        {:ok,
         %__MODULE__{
           available: available,
           total: min,
           max: max,
           min: min,
           max_uses: max_uses,
           create: create,
           destroy: destroy,
           uses: uses
         }}
    end
  end