# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`can?/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `can?/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `can?/2` missing

```elixir
defmodule Workflow do
  @moduledoc """
  A finite state machine for the lifecycle of an order.

  An order record is a plain map that always carries a `:state` key holding the
  current state atom. It moves through the following states:

      draft → submitted → approved → in_progress → completed

  with two side branches:

      submitted → rejected
      in_progress → cancelled

  The states `:completed`, `:rejected`, and `:cancelled` are terminal — no event
  can move an order out of them.

  This module is purely functional: it neither spawns nor relies on any
  processes, and it uses only the Elixir/OTP standard library.
  """

  @states [
    :draft,
    :submitted,
    :approved,
    :in_progress,
    :completed,
    :rejected,
    :cancelled
  ]

  # event => {from, to}
  @transitions %{
    submit: {:draft, :submitted},
    approve: {:submitted, :approved},
    reject: {:submitted, :rejected},
    start: {:approved, :in_progress},
    complete: {:in_progress, :completed},
    cancel: {:in_progress, :cancelled}
  }

  @doc """
  Build a new record.

  Returns `attrs` merged with `%{state: :draft}`. Any `:state` provided in
  `attrs` is overridden — a new record always starts in `:draft`.
  """
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, :draft)
  end

  @doc """
  Return the list of all seven state atoms.
  """
  @spec states() :: [atom()]
  def states, do: @states

  @doc """
  Attempt to apply `event` to `record`.

    * On success, returns `{:ok, updated_record}` with the `:state` field
      replaced by the destination state and all other fields preserved.
    * If `event` is not a valid transition out of the current state (including
      any event fired from a terminal state, or an unknown event), returns
      `{:error, :invalid_transition, current_state, event}`.
    * If the event is a valid edge but its guard rejects the record, returns
      `{:error, :guard_failed, current_state, event}`.
  """
  @spec transition(map(), atom()) ::
          {:ok, map()}
          | {:error, :invalid_transition, atom(), atom()}
          | {:error, :guard_failed, atom(), atom()}
  def transition(%{state: current} = record, event) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record) do
          {:ok, Map.put(record, :state, to)}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end

  @doc """
  Return `true` if `transition(record, event)` would succeed, otherwise `false`.
  """
  # TODO: @spec
  def can?(record, event) do
    match?({:ok, _}, transition(record, event))
  end

  # Guards: return true when the transition is permitted.

  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true
  defp guard(:submit, _record), do: false

  defp guard(:approve, %{approved_by: approved_by})
       when is_binary(approved_by) and approved_by != "",
       do: true

  defp guard(:approve, _record), do: false

  # All other transitions have no guard and always pass.
  defp guard(_event, _record), do: true
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
