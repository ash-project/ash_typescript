# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController do
  @moduledoc """
  Standalone Spark DSL for defining typed controller routes.

  Generates TypeScript path helper functions and a thin Phoenix controller
  from routes configured in the DSL. This is completely independent from
  `Ash.Resource` — routes contain colocated arguments and handler functions.

  ## Usage

      defmodule MyApp.Session do
        use AshTypescript.TypedController

        typed_controller do
          module_name MyAppWeb.SessionController

          route :login do
            method :post
            run fn conn, params -> Plug.Conn.send_resp(conn, 200, "OK") end
            argument :code, :string, allow_nil?: false
          end

          route :auth do
            method :get
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Auth") end
          end
        end
      end
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.TypedController.Dsl]]

  @doc """
  Sends `data` as the JSON response of the current route, formatted against the
  route's `returns` type.

  The result type is the route's decorated `returns` type in the manifest, so
  keys follow the manifest's client names (the configured
  `output_field_formatter` plus any `typescript_field_names` mappings) at every
  level, and the body matches the route's generated TypeScript result type.
  Use it from a route handler:

      post :login do
        returns :map
        constraints fields: [user_id: [type: :uuid, allow_nil?: false]]

        run fn conn, params ->
          user = log_in!(params.code)
          AshTypescript.TypedController.json(conn, %{user_id: user.id})
        end
      end

  Pass maps (with atom keys) for typed containers. Raises if the route does not
  declare `returns`, or if `conn` was not dispatched by a typed controller.
  """
  @spec json(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def json(conn, data) do
    Phoenix.Controller.json(conn, format_result(conn, data))
  end

  @doc """
  Formats `data` against the current route's `returns` type without sending it.

  See `json/2`. Useful when the response is sent some other way (e.g. with a
  custom status via `Plug.Conn.put_status/2` before `Phoenix.Controller.json/2`).
  """
  @spec format_result(Plug.Conn.t(), term()) :: term()
  def format_result(%Plug.Conn{private: private}, data) do
    case Map.fetch(private, :ash_typescript_manifest_route) do
      {:ok, %AshTypescript.Manifest.Route{returns: nil, name: name}} ->
        raise ArgumentError,
              "route #{inspect(name)} does not declare `returns`, so there is no " <>
                "result type to format against"

      {:ok, %AshTypescript.Manifest.Route{returns: returns}} ->
        manifest = AshTypescript.manifest()

        AshRpc.ValueFormatter.format(
          data,
          returns,
          [],
          :output,
          AshRpc.Runtime.from_manifest(manifest)
        )

      :error ->
        raise ArgumentError,
              "the conn was not dispatched by an AshTypescript typed controller route"
    end
  end
end
