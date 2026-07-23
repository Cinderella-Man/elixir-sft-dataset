# `RoleRegistry` — Runtime-Mutable Role Inheritance Graph

## Overview

This specification describes an Elixir GenServer module named `RoleRegistry` that maintains a **mutable, arbitrary role-inheritance graph** with **runtime grant/revoke of permissions**. The structure is not a fixed four-level ladder; it is a directed acyclic graph of roles that can be reshaped while the server is running.

Inheritance carries the following meaning: if `child` inherits `parent`, then `child` has every permission `parent` has, and everything `parent` inherits, transitively. Revoking a grant from `parent` must immediately affect what `child` can do.

The deliverable is the complete module in a single file with no external dependencies.

## API

The module exposes the public functions below. Each one takes the server `pid` or registered name as its first argument.

- `RoleRegistry.start_link(opts \\ [])` — starts the GenServer. Standard `GenServer` options such as `:name` are honored. Initial state has no roles, no inheritance edges, and no grants.
- `RoleRegistry.add_role(server, role)` — registers a role atom. It returns `:ok`, and it is idempotent: adding an existing role is fine.
- `RoleRegistry.add_inheritance(server, child, parent)` — records that `child` inherits `parent`'s permissions, transitively. Both roles must already exist; otherwise the call returns `{:error, :unknown_role}`. On success it returns `:ok`.
- `RoleRegistry.grant(server, role, resource, action)` — grants permission for `{resource, action}` directly to `role`. The role must exist, otherwise `{:error, :unknown_role}`. It returns `:ok` and is idempotent.
- `RoleRegistry.revoke(server, role, resource, action)` — removes a direct `{resource, action}` grant from `role`, affecting only that role's own grant and not inherited ones. It returns `:ok`.
- `RoleRegistry.can?(server, role, resource, action)` — returns `true` if `role`, or **any role it inherits transitively** (directly, or through a chain of inheritance edges), has a direct grant for `{resource, action}`; otherwise it returns `false`.

## Edge cases

- Adding an inheritance edge that would create a cycle — including a self-edge — must be rejected with `{:error, :cycle}`, and state must be left unchanged.
- `RoleRegistry.add_inheritance(server, child, parent)` with either role not yet registered returns `{:error, :unknown_role}`.
- `RoleRegistry.grant(server, role, resource, action)` for a role that does not exist returns `{:error, :unknown_role}`.
- `RoleRegistry.revoke(server, role, resource, action)` returns `:ok` even if the grant was not present.
- `RoleRegistry.can?(server, role, resource, action)` returns `false` for an unknown role.
- Re-adding an already registered role, and re-granting an already granted `{resource, action}` pair, are both no-ops that still return `:ok`.
