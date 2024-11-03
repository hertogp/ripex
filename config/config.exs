import Config

config :tesla, :adapter, Tesla.Adapter.Hackney

config :logger, :console,
  format: "$date $time [$level] $message\n",
  device: :standard_error
