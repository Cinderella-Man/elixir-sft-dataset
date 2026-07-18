  @doc """
  Executes the saga against an initial `context` map.

  Steps run strictly in the order they were added. Each successful
  step merges its result into the context under the step's name before
  the next step begins.

  On failure the compensating functions for all *completed* steps run
  in **reverse order**. Failures (or exceptions) inside a compensating
  function are caught, recorded, and never abort the remaining
  compensations.

  ## Return values

    * `{:ok, final_context}` — all steps succeeded.
    * `{:error, failed_step_name, reason, compensation_results}` — the
      step named `failed_step_name` returned `{:error, reason}`. The
      `compensation_results` keyword list contains one entry per
      compensated step, in reverse execution order.
  """
  @spec execute(t(), context()) :: execute_result()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run_steps(steps, [], context)
  end