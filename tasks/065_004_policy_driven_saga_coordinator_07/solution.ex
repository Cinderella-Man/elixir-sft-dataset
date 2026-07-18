  @doc """
  Appends a step. `opts` supports `:on_error` (`:continue` default, or `:abort`).
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
    policy = Keyword.get(opts, :on_error, :continue)

    unless policy in [:continue, :abort] do
      raise ArgumentError, "on_error must be :continue or :abort, got: #{inspect(policy)}"
    end

    step = %{name: name, action: action, compensation: compensation, policy: policy}
    %__MODULE__{saga | steps: steps ++ [step]}
  end