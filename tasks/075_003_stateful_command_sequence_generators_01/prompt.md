I need you to write a module for us called `CommandGenerators` — it's the piece I'm missing before I can do model-based property testing with `StreamData` and `ExUnitProperties`. What it needs to hand me is `StreamData` generators for *valid stateful command sequences*.

The whole reason this module exists is that it must never emit an invalid program. Every command in a sequence it generates has to satisfy its own precondition given the model state that all the earlier commands in that same sequence produced. So the generator threads a symbolic model along as it builds the list, and that means I can take any generated program, run it straight against the real system, and never filter or throw anything away.

There are two stateful generators I want in the public API, and they're independent of each other.

The first is `CommandGenerators.stack_program(max_length \\ 20)`, which gives me a list of `0..max_length` commands against a stack model. The commands are `{:push, integer}`, `:pop`, `:peek`, and `:clear`. The invariant I care about is that running the sequence against a stack must never `:pop` or `:peek` an empty stack — so `:pop`/`:peek` are only allowed to be generated when the modeled stack is non-empty, while `{:push, _}` and `:clear` are always fair game.

The second is `CommandGenerators.account_program(max_length \\ 20)`, which gives me a list of `0..max_length` commands against a bank-account model whose balance must never go negative. Commands here are `{:deposit, amount}` where amount is `1..1000`, and `{:withdraw, amount}` where amount is `1..current_balance`. A `:withdraw` can only be generated when the modeled balance is positive, and the amount it picks must not exceed the modeled balance at that point in the sequence.

One thing I want to be careful about: across many samples the full length range has to actually be reachable. The empty program (0 commands) must be an attainable output, and so must a program of exactly `max_length` commands — which incidentally means `max_length 0` yields only the empty program. Same goes for the endpoints of each amount and each command: given enough samples I should see deposits of both `1` and `1000`, withdrawals of both `1` and the entire current balance, and every single one of `:push`, `:pop`, `:peek`, `:clear`.

Both invariants have to be enforced *inside* the generators, by conditioning the set of available commands at each step on the current model state. I don't ever want a consumer of this to have to reach for `StreamData.filter/2`. And each generator needs to return a `%StreamData{}` struct so it composes with the standard `StreamData` combinators.

Send me the complete module in a single file, please. Only external dependency should be `stream_data`, nothing else.
