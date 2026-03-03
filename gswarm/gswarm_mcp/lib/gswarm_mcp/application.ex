defmodule GswarmMcp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Try to connect to gswarm node
    Task.start(fn -> connect_to_gswarm() end)

    children = [
      {Plug.Cowboy, scheme: :http, plug: GswarmMcp.Router, options: [port: 4001]}
    ]

    IO.puts("Generated children list...")
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GswarmMcp.Supervisor]
    IO.puts("Starting Supervisor...")
    result = Supervisor.start_link(children, opts)
    IO.inspect(result, label: "Supervisor Start Result")
    result
  end

  defp connect_to_gswarm do
    {:ok, hostname} = :inet.gethostname()
    node_name = :"gswarm@#{list_to_string(hostname)}"
    IO.puts("Attempting to connect to #{node_name}...")
    
    case Node.connect(node_name) do
      true -> IO.puts("✅ Connected to Gswarm node!")
      false -> 
        IO.puts("⚠️ Failed to connect to Gswarm node. Retrying in 5s...")
        Process.sleep(5000)
        connect_to_gswarm()
    end
  end

  defp list_to_string(list), do: List.to_string(list)
end
