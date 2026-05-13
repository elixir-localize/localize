# Supervision

Localize runs a small supervision tree at runtime — a data loader, a locale loader (which owns the locale-validation ETS table), a cache sweeper, a format cache, and the collation ICU table. By default this tree is started automatically when the `:localize` OTP application boots, so most consumers do not need to do anything.

Some applications prefer to mount Localize under their own supervision tree — typically to control startup ordering relative to other components (a database connection pool that loads locale-specific data, a background worker that formats messages on the first tick), or to run shutdown side-effects in a particular order. This guide describes that pattern.

## The default: auto-start

Out of the box, your `mix.exs` just lists the dependency:

```elixir
def deps do
  [
    {:localize, "~> 0.33"}
  ]
end
```

The `:localize` OTP application starts at boot and `Localize.Supervisor` comes up as part of the BEAM's application supervisor. No further configuration is required.

## Manual supervision

To mount Localize yourself, mark the dependency `runtime: false`. This tells Mix to compile the application but not to start it automatically:

```elixir
def deps do
  [
    {:localize, "~> 0.33", runtime: false}
  ]
end
```

Then add `Localize.Supervisor` to your application's `children` list:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      Localize.Supervisor,
      MyAppWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

### Ordering

`Localize.Supervisor` should start **before** any process that calls Localize functions at startup — message formatters, importers running on first-tick, anything in `Application.start_phases/0` that touches locale data.

It can start **after** anything Localize itself does not depend on at boot — repos, web endpoints, registries, etc. Localize reads its bundled CLDR data from `priv/` and does not depend on any consumer-side process.

### The `Localize.Supervisor` child spec

`Localize.Supervisor` exposes the standard `child_spec/1` callback, so the bare module name works as a child reference. If you prefer the tuple form, both of these are equivalent:

```elixir
children = [
  Localize.Supervisor,
  # …same as…
  {Localize.Supervisor, []}
]
```

There are no options today. The `options` argument exists so the tuple form remains valid if options are introduced in a later release.

### Side-effects that run once

`Localize.Supervisor.start_link/1` performs two pieces of one-time post-start work after its children are running:

1. Resolves `:supported_locales` from application env and caches it.
2. Reads every bundled supplemental data set so the atoms each one references (`:USD`, `:Latn`, `:arab`, `:gregorian`, …) are interned in the BEAM atom table. The 0.30.0 atom-DOS hardening uses `binary_to_existing_atom` at many lookup sites; without this eager-load valid input like `numberingSystem=arab` could surface as a bogus "unknown numbering system" error on a fresh BEAM.

Both side-effects are idempotent — starting the supervisor twice (which OTP would not let you do anyway, since the registered name is `Localize.Supervisor`) would not double-load anything.

### Verifying

After your application starts, the Localize tree should be visible alongside your own children:

```elixir
iex> :observer.start()
# Inspect `MyApp.Supervisor`; you should see `Localize.Supervisor` among
# its children, with the standard Localize processes below it.
```

You can also confirm via `Supervisor.which_children/1`:

```elixir
iex> MyApp.Supervisor |> Supervisor.which_children() |> Enum.map(&elem(&1, 0))
[MyApp.Repo, Localize.Supervisor, MyAppWeb.Endpoint]
```

## When to choose which mode

* **Auto-start (the default)** is right for almost every project. It is one fewer thing to think about, and OTP's startup semantics already handle the ordering between the `:localize` application and your own.

* **Manual supervision** is right when you need explicit ordering between Localize and another part of your own application, or when you maintain a multi-tenant host that wants to start and stop Localize as a unit alongside other tenant-scoped processes.

In either mode, the runtime behaviour of `Localize` is identical — the same processes, the same supplemental atoms, the same caches. The choice is purely about who owns the supervisor.
