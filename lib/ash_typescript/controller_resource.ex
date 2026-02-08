# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ControllerResource do
  @moduledoc """
  Spark DSL extension for configuring controller resources on Ash resources.

  This extension generates TypeScript path helper functions and a thin Phoenix
  controller from routes configured in the DSL. Only generic actions are
  supported — the resource is purely a container for controller logic.

  Actions handle their own response via `context.conn` (e.g. `render_inertia`,
  `redirect`, `render`). Users `import` third-party modules directly in the
  resource module, and the `run fn` closure captures that lexical scope.

  ## Usage

      defmodule MyApp.PageActions do
        use Ash.Resource,
          domain: MyApp.Domain,
          extensions: [AshTypescript.ControllerResource]

        import Inertia.Controller

        controller do
          module_name MyAppWeb.PageController

          route :home, :home, method: :get
          route :show_page, :show_page, method: :get
        end

        actions do
          action :home do
            run fn _input, ctx ->
              {:ok, render_inertia(ctx.conn, "Home")}
            end
          end

          action :show_page do
            run fn _input, ctx ->
              {:ok, render_inertia(ctx.conn, "ShowPage")}
            end
          end
        end
      end
  """

  defmodule RouteAction do
    @moduledoc """
    Struct representing a route action configuration.

    Defines the mapping between a named controller action and an Ash action,
    including HTTP method and documentation.
    """
    defstruct [
      :name,
      :action,
      :method,
      :description,
      :deprecated,
      __spark_metadata__: nil
    ]
  end

  @route_action %Spark.Dsl.Entity{
    name: :route,
    target: RouteAction,
    describe: """
    Define a route that maps a controller action to an Ash action.

    The HTTP method is required — there is no inference from action types since
    only generic actions are supported.
    """,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The controller action name (e.g. :home, :show_page)"
      ],
      action: [
        type: :atom,
        required: true,
        doc: "The Ash action name on the resource"
      ],
      method: [
        type: {:in, [:get, :post, :patch, :put, :delete]},
        required: true,
        doc: "The HTTP method. Required for all routes."
      ],
      description: [
        type: :string,
        required: false,
        doc: "JSDoc description for the generated TypeScript path helper"
      ],
      deprecated: [
        type: {:or, [:boolean, :string]},
        required: false,
        doc:
          "Mark this route as deprecated. Set to true for a default message, or provide a custom deprecation notice."
      ]
    ],
    args: [:name, :action]
  }

  @controller %Spark.Dsl.Section{
    name: :controller,
    describe: "Define controller routes for this resource",
    entities: [@route_action],
    schema: [
      module_name: [
        type: :atom,
        required: true,
        doc: "The module name for the generated Phoenix controller (e.g. MyAppWeb.PageController)"
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@controller],
    transformers: [AshTypescript.ControllerResource.Transformers.GenerateController],
    verifiers: [AshTypescript.ControllerResource.Verifiers.VerifyControllerResource]
end
