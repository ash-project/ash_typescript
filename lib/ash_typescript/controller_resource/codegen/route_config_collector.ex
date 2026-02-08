# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ControllerResource.Codegen.RouteConfigCollector do
  @moduledoc """
  Discovers all resources with `controller` DSL configuration across the app.
  """

  @doc """
  Gets all resources with controller configuration from the OTP application.

  Returns a list of tuples: `{resource, controller_module, routes}`
  where routes is a list of RouteAction structs.
  """
  def get_controller_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      domain
      |> Ash.Domain.Info.resources()
      |> Enum.filter(&AshTypescript.ControllerResource.Info.controller_resource?/1)
      |> Enum.map(fn resource ->
        controller_module =
          AshTypescript.ControllerResource.Info.controller_module_name!(resource)

        routes = AshTypescript.ControllerResource.Info.controller(resource)

        {resource, controller_module, routes}
      end)
    end)
  end
end
