  @doc """
  Registers a task with the runner.

  `opts` is a keyword list with:

    * `:depends_on` — list of `task_id`s this task depends on (default `[]`).
    * `:func` — a zero-arity function to execute (required).

  Submitting the same `task_id` again overwrites the previous definition.
  Returns `:ok`.
  """
  def submit(name, task_id, opts) do
    depends_on = Keyword.get(opts, :depends_on, [])

    func =
      case Keyword.fetch(opts, :func) do
        {:ok, f} when is_function(f, 0) ->
          f

        {:ok, _} ->
          raise ArgumentError, ":func must be a zero-arity function"

        :error ->
          raise ArgumentError, ":func option is required"
      end

    GenServer.call(name, {:submit, task_id, depends_on, func})
  end