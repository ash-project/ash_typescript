# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ControllerResource.RequestHandler do
  @moduledoc """
  Handles request lifecycle for controller resource routes.

  Only supports generic actions. Extracts actor/tenant from conn, puts
  `conn` in context, runs the action, and expects `{:ok, %Plug.Conn{}}`.
  On error, returns a 500 JSON fallback.

  The `conn` is available to actions via `context.conn`, allowing generic
  actions to handle their own response:

      action :show_page do
        run fn _input, ctx ->
          {:ok, render_inertia(ctx.conn, "MyPage", %{data: "hello"})}
        end
      end
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc """
  Handles a route request by executing the corresponding generic Ash action.

  The conn is passed to the action via `context.conn`. The action must
  return `{:ok, %Plug.Conn{}}`.
  """
  def handle(conn, domain, resource, action_name, params) do
    actor = Ash.PlugHelpers.get_actor(conn)
    tenant = Ash.PlugHelpers.get_tenant(conn)
    ash_context = Ash.PlugHelpers.get_context(conn) || %{}
    context = Map.put(ash_context, :conn, conn)

    input = extract_input(params)

    opts = [
      actor: actor,
      tenant: tenant,
      context: context,
      domain: domain
    ]

    case resource
         |> Ash.ActionInput.for_action(action_name, input, opts)
         |> Ash.run_action(opts) do
      {:ok, %Plug.Conn{} = conn} ->
        conn

      {:ok, unexpected} ->
        conn
        |> put_status(500)
        |> json(%{
          errors: [
            %{
              message:
                "Controller action must return %Plug.Conn{}, got: #{inspect(unexpected, limit: 50)}"
            }
          ]
        })

      {:error, error} ->
        conn
        |> put_status(500)
        |> json(%{errors: [%{message: Exception.message(error)}]})
    end
  end

  defp extract_input(params) do
    params
    |> Map.drop(["_format", "action", "controller"])
    |> Map.reject(fn {key, _} -> String.starts_with?(key, "_") end)
  end
end
