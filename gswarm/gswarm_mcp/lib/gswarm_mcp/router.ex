defmodule GswarmMcp.Router do
  use Plug.Router

  plug :debug_log
  plug :match
  plug :dispatch

  # Manual match to ensure Wrapper is called and path stripped
  match "/tidewave/*glob" do
    IO.puts("Manual match triggered. Glob: #{inspect(glob)}")
    # Update path_info so downstreams see relative path
    conn = %{conn | path_info: glob}
    conn = GswarmMcp.TidewaveWrapper.call(conn, [])
    if conn.state == :unset do
      send_resp(conn, 404, "Not Found (Tidewave)")
    else
      conn
    end
  end

  def debug_log(conn, _opts) do
    IO.puts("Router received request: #{conn.request_path}")
    conn
  end

  get "/" do
    send_resp(conn, 200, "Gswarm MCP Sidecar is running. Use /tidewave/mcp")
  end

  match _ do
    send_resp(conn, 404, "Not Found: #{conn.request_path}")
  end
end
