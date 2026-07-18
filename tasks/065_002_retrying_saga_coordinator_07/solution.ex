  @doc """
  Appends a step. `opts` supports `:max_attempts` (a positive integer, default 1).
  """
  @spec step(
          t(),
          term(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term()),
          keyword()
        ) :: t()
  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    unless is_integer(max_attempts) and max_attempts >= 1 do
      raise ArgumentError,
            "max_attempts must be a positive integer, got: #{inspect(max_attempts)}"
    end

    step = %{name: name, action: action, compensation: compensation, max_attempts: max_attempts}
    %__MODULE__{saga | steps: steps ++ [step]}
  end