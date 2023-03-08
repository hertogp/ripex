# Ripex


**WIP!**

RIPEStat api client and checks.

See https://stat.ripe.net/docs/02.data-api/

## CLI

`ripex` is the cli utility that supports some reports on specific topics
and yields a simple markdown document.

### Usage

```
   ripex [report] [flags] argument

   argument  is either an IP adress, prefix or AS number, examples:
             1.1.1.1, 1.0.0.0/8, AS333 or simply 333

   report    the name of the report you'd like to generate. When omitted
             ripex will generate some default small report.  It's ignored
             when an `-e endpoint` is given.

  flags:
  -h           shows help, including a list of available commands, and exits
  -c           produces csv output on stdout (if the command/endpoint supports it)
  -e endpoint  call a specific endpoint of the RIPEStat Data API.

```



### Examples

```bash

% ripex 1.1.1.1   # finds the as to which 1.1.1.1 belongs and yields the default report

```

## RIPE

This module is the main entry point for the [RIPEStat API](https://stat.ripe.net/docs/02.data-api/) client.



## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ripex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ripex, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ripex>.

