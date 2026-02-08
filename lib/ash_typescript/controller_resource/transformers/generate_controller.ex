# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ControllerResource.Transformers.GenerateController do
  @moduledoc """
  Spark transformer that generates a Phoenix controller module at compile time.

  The controller module name is specified in the DSL via `module_name`.
  Each route in the DSL becomes a controller action that delegates to
  `AshTypescript.ControllerResource.RequestHandler.handle/4`.
  """
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    controller_module =
      Spark.Dsl.Transformer.get_option(dsl_state, [:controller], :module_name)

    routes = Spark.Dsl.Transformer.get_entities(dsl_state, [:controller])
    resource = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)
    domain = Spark.Dsl.Transformer.get_persisted(dsl_state, :domain)

    action_functions =
      Enum.map(routes, fn route ->
        quote do
          def unquote(route.name)(conn, params) do
            AshTypescript.ControllerResource.RequestHandler.handle(
              conn,
              unquote(domain),
              unquote(resource),
              unquote(route.action),
              params
            )
          end
        end
      end)

    Module.create(
      controller_module,
      quote do
        use Phoenix.Controller, formats: [:html]

        unquote_splicing(action_functions)
      end,
      Macro.Env.location(__ENV__)
    )

    {:ok, dsl_state}
  end
end
