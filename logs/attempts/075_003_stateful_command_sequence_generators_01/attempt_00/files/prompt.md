Write me an Elixir module called `CommandGenerators` that provides `StreamData` generators for **valid stateful command sequences**, intended for model-based property testing with `StreamData` and `ExUnitProperties`.

The point of these generators is that they never emit an invalid program: each command in a generated sequence must satisfy its **precondition** given the model state produced by all the commands before it. The generator threads a symbolic model as it builds the sequence, so a consumer can run every generated program against a real system without ever having to filter or discard sequences.

I need two independent stateful generators in the public API:

- `CommandGenerators.stack_program(max_length \\ 20)` — produces a list of `0..max_length` commands for a stack model. Commands are `{:push, integer}`, `:pop`, `:peek`, and `:clear`. The invariant: running the sequence against a stack must never `:pop` or `:peek` an empty stack. So `:pop`/`:peek` may only be generated when the modeled stack is non-empty; `{:push, _}` and `:clear` are always allowed.

- `CommandGenerators.account_program(max_length \\ 20)` — produces a list of `0..max_length` commands for a bank-account model whose balance must never go negative. Commands are `{:deposit, amount}` (amount `1..1000`) and `{:withdraw, amount}` (amount `1..current_balance`). A `:withdraw` may only be generated when the modeled balance is positive, and its amount must not exceed the modeled balance at that point.

Both invariants must be enforced *inside* the generators by conditioning each step's available commands on the current model state — consumers must never need `StreamData.filter/2`. Each generator must return a `%StreamData{}` struct that composes with the standard `StreamData` combinators.

Give me the complete module in a single file. Use only `stream_data` as an external dependency, no others.