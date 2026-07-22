Write me an Elixir module called `Saga` that implements the Saga pattern **with a durable journal and crash-resumable execution**. Every run emits an ordered event journal, and a partially-completed run can be resumed from that journal without re-running steps that already finished.

Public API:
- `Saga.new()` — creates a new, empty saga struct.
- `Saga.step(saga, name, action_fn, compensate_fn)` — appends a named step. `action_fn` receives the accumulated context and returns `{:ok, result}` or `{:error, reason}`; on success the result is merged under `name`. `compensate_fn` receives the context; its return value is recorded but never fails the chain.
- `Saga.execute(saga, context)` — runs all steps from the beginning.
- `Saga.resume(saga, context, journal)` — resumes from a previously produced journal.

Journal format — a list of events in **chronological** order:
- `{:completed, name, result}` — a step finished successfully with `result`.
- `{:failed, name, reason}` — a step returned `{:error, reason}`.
- `{:compensated, name, value}` — a completed step's compensation ran, returning `value`.

Return values (note the extra journal element):
- `{:ok, final_context, journal}` on full success.
- `{:error, failed_step_name, reason, compensation_results, journal}` on failure, where `compensation_results` is a keyword list `[step_name: value]` in reverse call order and `journal` is the complete chronological event list.

Resume semantics:
- `resume/3` reconstructs the context by merging every `{:completed, name, result}` from the incoming journal (under `name`), **without** re-invoking those actions. Assume completed steps form a prefix of the step list.
- It then runs the remaining steps, appending new events to (a copy of) the incoming journal's completed events so the returned journal stays chronological.
- If a later step fails during resume, **all** completed steps — those replayed from the journal *and* those newly run — are compensated in reverse order, using each step's compensating function from the saga definition.
- An empty journal makes `resume/3` behave exactly like `execute/2`.

Other behaviours: steps run strictly in order; each action/compensation sees the accumulated context; a raising compensating function must not abort the remaining compensations (catch and record it). Plain module with a struct — no GenServer, no processes, no external dependencies. Give me the complete implementation in a single file.