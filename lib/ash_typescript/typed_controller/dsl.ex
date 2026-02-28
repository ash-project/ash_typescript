# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Dsl do
  @moduledoc """
  Spark DSL extension for defining typed controller routes.

  This extension generates TypeScript path helper functions and a thin Phoenix
  controller from routes configured in the DSL. Unlike `AshTypescript.ControllerResource`,
  this is a standalone Spark DSL — not attached to `Ash.Resource`.

  Routes contain colocated arguments and handler functions (inline closures or
  handler modules implementing `AshTypescript.TypedController.Route`).

  ## Usage

  Three syntaxes are supported for defining routes:

      defmodule MyApp.Session do
        use AshTypescript.TypedController

        typed_controller do
          module_name MyAppWeb.SessionController

          # Verb shortcut (preferred)
          post :login do
            run fn conn, params -> Plug.Conn.send_resp(conn, 200, "OK") end
            argument :code, :string, allow_nil?: false
            argument :remember_me, :boolean
          end

          # Positional method arg
          route :auth, :get do
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Auth") end
          end

          # Method defaults to :get when omitted
          route :home do
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Home") end
          end
        end
      end
  """

  defmodule RouteArgument do
    @moduledoc """
    Struct representing a route argument configuration.
    """
    defstruct [
      :name,
      :type,
      :constraints,
      :default,
      allow_nil?: true,
      __spark_metadata__: nil
    ]
  end

  defmodule Route do
    @moduledoc """
    Struct representing a route configuration.

    Defines a controller action with its HTTP method, handler, and arguments.
    """
    defstruct [
      :name,
      :method,
      :run,
      :description,
      :deprecated,
      :zod_schema_name,
      :namespace,
      see: [],
      arguments: [],
      __spark_metadata__: nil
    ]
  end

  @route_argument %Spark.Dsl.Entity{
    name: :argument,
    target: RouteArgument,
    describe: "Define an argument for this route.",
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The argument name"
      ],
      type: [
        type: {:or, [:atom, {:tuple, [:atom, :keyword_list]}]},
        required: true,
        doc: "The Ash type (e.g. :string, :boolean, :integer)"
      ],
      constraints: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Type constraints"
      ],
      allow_nil?: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Whether this argument can be nil. Set to false to make it required."
      ],
      default: [
        type: :any,
        required: false,
        doc: "Default value for this argument"
      ]
    ],
    args: [:name, :type]
  }

  # Schema options shared by @route and verb shortcut entities
  @common_route_schema [
    name: [
      type: :atom,
      required: true,
      doc: "The controller action name (e.g. :login, :auth)"
    ],
    run: [
      type: {:or, [{:fun, 2}, :atom]},
      required: true,
      doc:
        "The handler — an fn/2 closure or a module implementing AshTypescript.TypedController.Route"
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
    ],
    see: [
      type: {:list, :atom},
      required: false,
      default: [],
      doc: "List of related route names to reference in JSDoc @see tags."
    ],
    zod_schema_name: [
      type: :string,
      required: false,
      doc:
        "Override the generated Zod schema name (used as-is for the exported const). Use when the default name collides with an RPC action's Zod schema."
    ],
    namespace: [
      type: :string,
      required: false,
      doc:
        "Namespace for organizing this route into a separate file (becomes the filename). Overrides controller-level namespace."
    ]
  ]

  @route %Spark.Dsl.Entity{
    name: :route,
    target: Route,
    describe: """
    Define a route that maps a controller action to a handler.

    Supports three syntaxes:
    - `route :name, :post do ... end` (positional method arg)
    - `route :name do ... end` (defaults to GET)
    - `post :name do ... end` (verb shortcut)

    The handler can be an inline function (fn/2) or a module implementing
    the `AshTypescript.TypedController.Route` behaviour. Handlers receive
    `(conn, params)` and must return a `%Plug.Conn{}`.
    """,
    entities: [arguments: [@route_argument]],
    schema:
      [
        method: [
          type: {:in, [:get, :post, :patch, :put, :delete]},
          required: false,
          default: :get,
          doc: "The HTTP method. Defaults to :get."
        ]
      ] ++ @common_route_schema,
    args: [:name, {:optional, :method}]
  }

  # Verb shortcut entities — e.g. `get :login do ... end`, `post :login do ... end`
  @verb_shortcuts (for method <- [:get, :post, :patch, :put, :delete] do
                     %Spark.Dsl.Entity{
                       name: method,
                       target: Route,
                       describe:
                         "Define a #{method |> to_string() |> String.upcase()} route. Shorthand for `route :name, :#{method}`.",
                       entities: [arguments: [@route_argument]],
                       auto_set_fields: [method: method],
                       schema: @common_route_schema,
                       args: [:name]
                     }
                   end)

  @typed_controller %Spark.Dsl.Section{
    name: :typed_controller,
    describe: "Define typed controller routes",
    entities: [@route | @verb_shortcuts],
    schema: [
      module_name: [
        type: :atom,
        required: true,
        doc:
          "The module name for the generated Phoenix controller (e.g. MyAppWeb.SessionController)"
      ],
      namespace: [
        type: :string,
        required: false,
        doc:
          "Default namespace (filename) for all routes in this controller. Can be overridden per-route."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@typed_controller],
    transformers: [AshTypescript.TypedController.Transformers.GenerateController],
    verifiers: [AshTypescript.TypedController.Verifiers.VerifyTypedController]
end
