# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.PlainDataTest do
  # Typed controller route `returns` and typed channel publication `returns`
  # are plain data, checked when the manifest module compiles: resources,
  # embedded resources, unions and recursive named types are rejected at any
  # depth, declared custom types and NewTypes included. Publications must
  # also have a `returns` that is a typed map at the top level. Fixture
  # modules are created with `Module.create/3` under fixed names, so the
  # tests aren't async.
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.PlainDataTest, as: T

  @moduletag :ash_typescript

  @resource_hint "Declare a typed map and build it from the record, for example " <>
                   "`returns: :map, constraints: [fields: [email: [type: :string]]]` " <>
                   "with `%{email: user.email}`."
  @union_hint "Use a typed map with a field per variant (all `allow_nil?: true`)."
  @cycle_hint "Expand it to a fixed depth or send an untyped `:map` field."
  @non_map_hint "Phoenix only pushes JSON objects."
  @untyped_hint "Declare its `fields`"
  @no_returns_hint "Set `returns:` with `constraints`, or `transform:` a calculation typed as a map"

  defmodule Node do
    @moduledoc false
    # A self-referential typed map.
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [
        fields: [
          label: [type: :string],
          children: [type: {:array, AshTypescript.Manifest.PlainDataTest.Node}, init?: false]
        ]
      ]
  end

  defmodule Owned do
    @moduledoc false
    # A NewType over a typed map whose field is a resource.
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [
        fields: [owner: [type: :struct, constraints: [instance_of: AshTypescript.Test.User]]]
      ]
  end

  defmodule Envelope do
    @moduledoc false
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [fields: [title: [type: :string], raw: [type: :term]]]
  end

  defmodule Title do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string
  end

  defmodule PlainToken do
    @moduledoc false
    defstruct [:value]
  end

  defmodule MapStorage do
    @moduledoc false
    defmacro __using__(opts) do
      storage = Keyword.get(opts, :storage, :map)

      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: unquote(storage)
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  defmodule Holder do
    @moduledoc false
    # Declared in `custom_types` with a resource field.
    use MapStorage
  end

  defmodule Either do
    @moduledoc false
    # Declared in `custom_types` with a union field.
    use MapStorage
  end

  defmodule Tree do
    @moduledoc false
    # Declared in `custom_types` with a field of its own type.
    use MapStorage
  end

  defmodule Opaque do
    @moduledoc false
    # Not map-like and not declared: an opaque custom type.
    use MapStorage, storage: :string

    def typescript_type_name, do: "string"
  end

  @declared_types (quote do
                     custom_types do
                       map AshTypescript.Manifest.PlainDataTest.Holder do
                         field :name, :string

                         field :owner, :struct,
                           constraints: [instance_of: AshTypescript.Test.User]
                       end

                       map AshTypescript.Manifest.PlainDataTest.Either do
                         field :choice, :union,
                           constraints: [types: [text: [type: :string], number: [type: :integer]]]
                       end

                       map AshTypescript.Manifest.PlainDataTest.Tree do
                         field :label, :string
                         field :children, {:array, AshTypescript.Manifest.PlainDataTest.Tree}
                       end
                     end
                   end)

  # -- helpers ---------------------------------------------------------------

  defp compile_manifest!(name, opts, body) do
    module = Module.concat(T, name)

    Module.create(
      module,
      quote do
        use AshTypescript.Manifest,
            unquote(
              Keyword.merge(
                [otp_app: :ash_typescript, domains: [AshTypescript.Test.SecondDomain]],
                opts
              )
            )

        unquote(body)
      end,
      Macro.Env.location(__ENV__)
    )

    AshTypescript.manifest(module)
  end

  defp define_controller!(name, returns, constraints) do
    module = Module.concat(T, name)

    Module.create(
      module,
      quote do
        use AshTypescript.TypedController

        typed_controller do
          module_name unquote(Module.concat(module, Controller))

          get :result do
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            returns unquote(returns)
            constraints unquote(constraints)
          end
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module
  end

  defp define_feed!(name, publish_opts, calculations \\ nil) do
    resource = Module.concat(T, name)
    channel = Module.concat(resource, Channel)
    prefix = Macro.underscore(inspect(name))

    Module.create(
      resource,
      quote do
        use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

        pub_sub do
          module AshTypescript.Test.TestEndpoint
          prefix unquote(prefix)

          publish :create,
                  [:id],
                  unquote([event: "pushed", public?: true] ++ publish_opts)
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        unquote(calculations)

        actions do
          defaults [:read, :create]
        end
      end,
      Macro.Env.location(__ENV__)
    )

    Module.create(
      channel,
      quote do
        use Phoenix.Channel
        use AshTypescript.TypedChannel

        typed_channel do
          topic unquote(prefix <> ":*")

          resource unquote(resource) do
            publish :pushed
          end
        end

        def join(_topic, _payload, socket), do: {:ok, socket}
      end,
      Macro.Env.location(__ENV__)
    )

    {resource, channel}
  end

  defp quietly(fun), do: elem(ExUnit.CaptureIO.with_io(:stderr, fun), 0)

  defp rejected!(fun) do
    error = assert_raise Spark.Error.DslError, fn -> quietly(fun) end
    {error, Exception.message(error)}
  end

  defp route_rejected!(name, returns, constraints, body \\ nil) do
    {error, message} =
      rejected!(fn ->
        controller = define_controller!(name, returns, constraints)
        compile_manifest!(Module.concat(name, Manifest), [typed_controllers: [controller]], body)
      end)

    controller = Module.concat(T, name)
    # Spark sets `module` to the manifest module; the message names the controller.
    assert error.module == Module.concat(controller, Manifest)
    assert error.path == [:typed_controller, :result]
    assert message =~ "#{inspect(controller)} route :result returns "
    message
  end

  defp route_accepted!(name, returns, constraints) do
    manifest =
      quietly(fn ->
        controller = define_controller!(name, returns, constraints)
        compile_manifest!(Module.concat(name, Manifest), [typed_controllers: [controller]], nil)
      end)

    assert %AshTypescript.Manifest.Route{} =
             Custom.route(manifest, Module.concat(T, name), :result)
  end

  defp publication_rejected!(name, publish_opts, calculations \\ nil, body \\ nil) do
    {error, message} =
      rejected!(fn ->
        {_resource, channel} = define_feed!(name, publish_opts, calculations)
        compile_manifest!(Module.concat(name, Manifest), [typed_channels: [channel]], body)
      end)

    resource = Module.concat(T, name)
    channel = Module.concat(resource, Channel)
    assert error.module == Module.concat(resource, Manifest)
    assert error.path == [:typed_channel]

    assert message =~
             "#{inspect(channel)} publication \"pushed\" of #{inspect(resource)} "

    message
  end

  defp publication_accepted!(name, publish_opts, calculations \\ nil) do
    manifest =
      quietly(fn ->
        {_resource, channel} = define_feed!(name, publish_opts, calculations)
        compile_manifest!(Module.concat(name, Manifest), [typed_channels: [channel]], nil)
      end)

    resource = Module.concat(T, name)

    assert %AshTypescript.Manifest.Publication{returns: %Ash.Info.Manifest.Type{}} =
             Custom.publication(manifest, Module.concat(resource, Channel), resource, "pushed")
  end

  # -- routes ------------------------------------------------------------------

  describe "route returns rejected at any depth" do
    test "an embedded resource" do
      message = route_rejected!(RouteEmbedded, AshTypescript.Test.TaskMetadata, [])

      assert message =~
               "returns an embedded resource, AshTypescript.Test.TaskMetadata, at returns.\n\n"

      assert message =~ "Route results and channel payloads are plain data"
      assert message =~ @resource_hint
    end

    test "a :struct instance_of a domain resource" do
      message =
        route_rejected!(RouteStruct, :struct, instance_of: AshTypescript.Test.User)

      assert message =~ "returns a resource, AshTypescript.Test.User, at returns.\n\n"
      assert message =~ @resource_hint
    end

    test "a resource in an array item's field" do
      message =
        route_rejected!(RouteArrayItem, {:array, :map},
          items: [
            fields: [owner: [type: :struct, constraints: [instance_of: AshTypescript.Test.User]]]
          ]
        )

      assert message =~ "returns a resource, AshTypescript.Test.User, at returns → [] → owner."
      assert message =~ @resource_hint
    end

    test "an embedded resource in a typed map field" do
      message =
        route_rejected!(RouteMapField, :map,
          fields: [meta: [type: AshTypescript.Test.TaskMetadata]]
        )

      assert message =~
               "returns an embedded resource, AshTypescript.Test.TaskMetadata, at returns → meta."
    end

    test "a resource in a field of a NewType over a typed map" do
      message = route_rejected!(RouteNewType, T.Owned, [])

      assert message =~ "returns a resource, AshTypescript.Test.User, at returns → owner."
      assert message =~ @resource_hint
    end

    test "a union at the top" do
      message =
        route_rejected!(RouteUnion, :union,
          types: [text: [type: :string], number: [type: :integer]]
        )

      assert message =~ "returns a union, at returns.\n\n"
      assert message =~ @union_hint
    end

    test "a union in a field" do
      message =
        route_rejected!(RouteNestedUnion, :map,
          fields: [
            choice: [
              type: :union,
              constraints: [types: [text: [type: :string], number: [type: :integer]]]
            ]
          ]
        )

      assert message =~ "returns a union, at returns → choice.\n\n"
      assert message =~ @union_hint
    end

    test "a recursive NewType" do
      message = route_rejected!(RouteRecursive, T.Node, [])

      assert message =~
               "returns a recursive type, #{inspect(T.Node)}, at returns → children → [].\n\n"

      assert message =~ @cycle_hint
    end
  end

  describe "route returns accepted" do
    test "scalars, enums and untyped values at the top" do
      route_accepted!(RouteString, :string, [])
      route_accepted!(RouteEnum, AshTypescript.Test.Todo.Status, [])
      route_accepted!(RouteTerm, :term, [])
      route_accepted!(RouteUntypedMap, :map, [])
      route_accepted!(RouteTitle, T.Title, [])
    end

    test "typed containers and arrays of them" do
      route_accepted!(RouteTypedMap, :map, fields: [email: [type: :string]])
      route_accepted!(RouteArray, {:array, :map}, items: [fields: [email: [type: :string]]])
      route_accepted!(RouteKeyword, :keyword, fields: [count: [type: :integer]])

      route_accepted!(RouteTuple, :tuple,
        fields: [left: [type: :integer], right: [type: :string]]
      )

      route_accepted!(RouteTypedStruct, AshTypescript.Test.TodoStatistics, [])
      route_accepted!(RouteEnvelope, T.Envelope, [])
    end

    test "an untyped field in a typed map" do
      route_accepted!(RouteRawField, :map, fields: [raw: [type: :term], blob: [type: :map]])
    end
  end

  describe "manifest roots" do
    test "a resource reached by a route argument is still in the manifest" do
      # Arguments are outside the plain-data rule, so their resources stay
      # `always:` roots; resources in `returns` don't need to be.
      controller = Module.concat(T, ArgumentRoot)

      manifest =
        quietly(fn ->
          Module.create(
            controller,
            quote do
              use AshTypescript.TypedController

              typed_controller do
                module_name AshTypescript.Manifest.PlainDataTest.ArgumentRoot.Controller

                post :save do
                  run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                  argument :metadata, AshTypescript.Test.TaskMetadata
                end
              end
            end,
            Macro.Env.location(__ENV__)
          )

          compile_manifest!(ArgumentRootManifest, [typed_controllers: [controller]], nil)
        end)

      assert Map.has_key?(
               AshRpc.Manifest.resource_lookup(manifest),
               AshTypescript.Test.TaskMetadata
             )
    end
  end

  # -- declared custom types -----------------------------------------------------

  describe "declared custom types" do
    test "a route returning one with a resource field is rejected at that field" do
      message = route_rejected!(RouteHolder, T.Holder, [], @declared_types)

      assert message =~ "returns a resource, AshTypescript.Test.User, at returns → owner."
      assert message =~ @resource_hint
    end

    test "a route returning one with a union field is rejected at that field" do
      message = route_rejected!(RouteEither, T.Either, [], @declared_types)

      assert message =~ "returns a union, at returns → choice."
      assert message =~ @union_hint
    end

    test "a route returning a recursive one is rejected" do
      message = route_rejected!(RouteTree, T.Tree, [], @declared_types)

      assert message =~
               "returns a recursive type, #{inspect(T.Tree)}, at returns → children → []."

      assert message =~ @cycle_hint
    end

    test "a publication returning one with a resource field is rejected at that field" do
      message =
        publication_rejected!(
          FeedHolder,
          [returns: T.Holder, transform: quote(do: fn _ -> %{} end)],
          nil,
          @declared_types
        )

      assert message =~ "returns a resource, AshTypescript.Test.User, at returns → owner."
    end

    test "a publication returning one with a union field is rejected at that field" do
      message =
        publication_rejected!(
          FeedEither,
          [returns: T.Either, transform: quote(do: fn _ -> %{} end)],
          nil,
          @declared_types
        )

      assert message =~ "returns a union, at returns → choice."
    end
  end

  # -- publications --------------------------------------------------------------

  defp nothing, do: quote(do: fn _ -> nil end)

  describe "publication returns rejected" do
    test "a resource" do
      message =
        publication_rejected!(FeedResource,
          returns: :struct,
          constraints: [instance_of: AshTypescript.Test.User],
          transform: nothing()
        )

      assert message =~ "returns a resource, AshTypescript.Test.User, at returns.\n\n"
      assert message =~ @resource_hint
    end

    test "an embedded resource" do
      message =
        publication_rejected!(FeedEmbedded,
          returns: AshTypescript.Test.TaskMetadata,
          transform: nothing()
        )

      assert message =~
               "returns an embedded resource, AshTypescript.Test.TaskMetadata, at returns."
    end

    test "a union at the top and nested" do
      top =
        publication_rejected!(FeedUnion,
          returns: :union,
          constraints: [types: [text: [type: :string], number: [type: :integer]]],
          transform: nothing()
        )

      assert top =~ "returns a union, at returns.\n\n"

      nested =
        publication_rejected!(FeedNestedUnion,
          returns: :map,
          constraints: [
            fields: [
              choice: [
                type: :union,
                constraints: [types: [text: [type: :string], number: [type: :integer]]]
              ]
            ]
          ],
          transform: nothing()
        )

      assert nested =~ "returns a union, at returns → choice.\n\n"
      assert nested =~ @union_hint
    end

    test "a recursive NewType" do
      message = publication_rejected!(FeedRecursive, returns: T.Node, transform: nothing())

      assert message =~
               "returns a recursive type, #{inspect(T.Node)}, at returns → children → []."
    end

    test "a scalar" do
      message = publication_rejected!(FeedString, returns: :string, transform: nothing())

      assert message =~ "returns Ash.Type.String, which is not a typed map.\n\n"
      assert message =~ @non_map_hint
    end

    test "an enum" do
      message =
        publication_rejected!(FeedEnum,
          returns: AshTypescript.Test.Todo.Status,
          transform: nothing()
        )

      assert message =~ "returns AshTypescript.Test.Todo.Status, which is not a typed map."
      assert message =~ @non_map_hint
    end

    test "an array, even of typed maps" do
      message =
        publication_rejected!(FeedArray,
          returns: {:array, :map},
          constraints: [items: [fields: [title: [type: :string]]]],
          transform: nothing()
        )

      assert message =~ "returns an array, which is not a typed map."
      assert message =~ @non_map_hint

      untyped_items =
        publication_rejected!(FeedUntypedArray, returns: {:array, :map}, transform: nothing())

      assert untyped_items =~ "returns an array, which is not a typed map."
    end

    test "a NewType over a scalar" do
      message = publication_rejected!(FeedTitle, returns: T.Title, transform: nothing())

      assert message =~ "returns #{inspect(T.Title)}, which is not a typed map."
    end

    test "an opaque custom type" do
      message = publication_rejected!(FeedOpaque, returns: T.Opaque, transform: nothing())

      assert message =~ "returns #{inspect(T.Opaque)}, which is not a typed map."
      assert message =~ "as a `map` in your manifest module's `custom_types` section"
    end

    test ":term" do
      message = publication_rejected!(FeedTerm, returns: :term, transform: nothing())

      assert message =~ "returns untyped data, Ash.Type.Term.\n\n"
      assert message =~ @untyped_hint
    end

    test "an unconstrained :map" do
      message = publication_rejected!(FeedUntypedMap, returns: :map, transform: nothing())

      assert message =~ "returns untyped data, Ash.Type.Map.\n\n"
      assert message =~ @untyped_hint
    end

    test "no returns" do
      message = publication_rejected!(FeedNoReturns, [])

      assert message =~ "has no `returns`.\n\n"
      assert message =~ @no_returns_hint
    end
  end

  describe "publication returns accepted" do
    test "typed containers" do
      publication_accepted!(FeedTypedMap,
        returns: :map,
        constraints: [fields: [title: [type: :string]]],
        transform: nothing()
      )

      publication_accepted!(FeedKeyword,
        returns: :keyword,
        constraints: [fields: [count: [type: :integer]]],
        transform: nothing()
      )

      publication_accepted!(FeedTuple,
        returns: :tuple,
        constraints: [fields: [left: [type: :integer], right: [type: :string]]],
        transform: nothing()
      )

      publication_accepted!(FeedTypedStruct,
        returns: AshTypescript.Test.TodoStatistics,
        transform: nothing()
      )
    end

    test "a :struct with fields" do
      publication_accepted!(FeedStructFields,
        returns: :struct,
        constraints: [fields: [title: [type: :string]]],
        transform: nothing()
      )
    end

    test "a NewType over a typed map, with an untyped field" do
      publication_accepted!(FeedEnvelope, returns: T.Envelope, transform: nothing())
    end

    test "an untyped nested field" do
      publication_accepted!(FeedRawField,
        returns: :map,
        constraints: [fields: [raw: [type: :term]]],
        transform: nothing()
      )
    end

    test "a transform calculation typed :auto as a map expression" do
      publication_accepted!(
        FeedCalc,
        [transform: :card],
        quote do
          calculations do
            calculate :card, :auto, expr(%{title: unquote(Macro.var(:title, nil))}) do
              public? true
            end
          end
        end
      )
    end
  end

  # -- ordering with the untyped-struct check -----------------------------------

  describe "untyped structs" do
    test "keep the untyped-struct wording, without the resource alternative" do
      message =
        publication_rejected!(FeedPlainToken,
          returns: :struct,
          constraints: [instance_of: T.PlainToken],
          transform: nothing()
        )

      assert message =~ "returns an untyped struct, #{inspect(T.PlainToken)}, at returns."
      assert message =~ "* an Ash.TypedStruct"
      refute message =~ "`instance_of` an Ash resource"
    end

    test "are reported before the plain-data rule when both apply" do
      message =
        publication_rejected!(FeedPlainTokens,
          returns: {:array, :struct},
          constraints: [items: [instance_of: T.PlainToken]],
          transform: nothing()
        )

      assert message =~ "returns an untyped struct, #{inspect(T.PlainToken)}, at returns → []."
      refute message =~ "which is not a typed map"
    end

    test "are reported before the plain-data rule on a route too" do
      message =
        route_rejected!(RoutePlainTokens, :map,
          fields: [
            choice: [
              type: :union,
              constraints: [types: [text: [type: :string], number: [type: :integer]]]
            ],
            token: [type: :struct, constraints: [instance_of: T.PlainToken]]
          ]
        )

      assert message =~ "returns an untyped struct, #{inspect(T.PlainToken)}, at returns → token."
      refute message =~ "a union"
    end

    test "on a route, without the resource alternative" do
      message = route_rejected!(RoutePlainToken, :struct, instance_of: T.PlainToken)

      assert message =~ "returns an untyped struct, #{inspect(T.PlainToken)}, at returns."
      refute message =~ "`instance_of` an Ash resource"
    end

    test "on a route argument, with the resource alternative" do
      # Arguments are outside the plain-data rule and may be resources.
      controller = Module.concat(T, ArgumentPlainToken)

      {error, message} =
        rejected!(fn ->
          Module.create(
            controller,
            quote do
              use AshTypescript.TypedController

              typed_controller do
                module_name AshTypescript.Manifest.PlainDataTest.ArgumentPlainToken.Controller

                post :save do
                  run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end

                  argument :token, :struct,
                    constraints: [instance_of: AshTypescript.Manifest.PlainDataTest.PlainToken]
                end
              end
            end,
            Macro.Env.location(__ENV__)
          )

          compile_manifest!(ArgumentPlainTokenManifest, [typed_controllers: [controller]], nil)
        end)

      assert error.path == [:typed_controller, :save]

      assert message =~
               "#{inspect(controller)} route :save accepts an untyped struct, " <>
                 "#{inspect(T.PlainToken)}, at argument :token."

      assert message =~ "* `instance_of` an Ash resource"
    end
  end
end
