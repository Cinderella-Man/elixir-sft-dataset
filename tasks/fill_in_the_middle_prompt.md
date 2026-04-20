So I have this module which is designed to be single-shot SFT answer.
I would like to now to create "fill-in-the-middle" tasks out of it.
I would like to create tasks for:
- `apply_leak/1`
- `execute_in_closed/2`
- `execute_in_half_open/2`

Can you generate prompts that could be given as tasks to implement those functions (one at the time).

Here's an example of prompt for similar task:

```
Implement the private `handle_closed/2` function. It should execute the provided zero-arity function using `execute/1`.

If the execution succeeds, reset `failure_count` to 0 and return the result in the GenServer reply.

If the execution fails, increment `failure_count`. If the updated count is greater than or equal to `failure_threshold`, transition the circuit to the `:open` state using `trip_open/1`.

In all cases, return the result produced by `execute/1` in the GenServer reply along with the updated state.
```

This will be given together with the whole module with the function's body erased (just # TODO inside instead)

Here's the whole module:

```elixir
PASTE SINGLE-SHOT (01) SOLUTION HERE
```

And here's the original prompt that generated the whole module:

```
PASTE SINGLE-SHOT (01) PROMPT HERE
```