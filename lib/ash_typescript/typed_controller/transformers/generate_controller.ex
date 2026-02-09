# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Transformers.GenerateController do
  @moduledoc """
  Spark transformer that generates a Phoenix controller module at compile time.

  Each route in the DSL becomes a controller action that delegates to
  `AshTypescript.TypedController.RequestHandler.handle/4`.
  """
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    controller_module =
      Spark.Dsl.Transformer.get_option(dsl_state, [:typed_controller], :module_name)

    routes = Spark.Dsl.Transformer.get_entities(dsl_state, [:typed_controller])
    source_module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)

    action_functions =
      Enum.map(routes, fn route ->
        quote do
          def unquote(route.name)(conn, params) do
            AshTypescript.TypedController.RequestHandler.handle(
              conn,
              unquote(source_module),
              unquote(route.name),
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
