defmodule GswarmMcp.TidewaveWrapper do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
     IO.puts("Wrapper called with path: #{inspect(conn.path_info)}")
     
     config = %{
       allow_remote_access: true,
       phoenix_endpoint: nil,
       team: [],
       inspect_opts: [charlists: :as_lists, limit: 50, pretty: true]
     }
     conn = put_private(conn, :tidewave_config, config)
     
     IO.puts("Calling Tidewave.Router...")
     conn = Tidewave.Router.call(conn, Tidewave.Router.init([]))
     IO.puts("Tidewave.Router returned. State: #{conn.state}, Status: #{conn.status}")
     
     if conn.state == :unset do
       IO.puts("!!! Router failed to send response !!!")
       IO.puts("Path info: #{inspect(conn.path_info)}")
       send_resp(conn, 500, "Wrapper Error: Tidewave Router returned without sending response")
     else
       conn
     end
  end
end
