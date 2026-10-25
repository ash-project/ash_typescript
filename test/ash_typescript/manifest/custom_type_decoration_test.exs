# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.CustomTypeDecorationTest do
  # Declared custom-type fields reach decoration: the manifest's
  # `custom_types` entries, type callbacks and built-ins turn custom types in
  # RPC resources, typed controller routes and typed channel publications into
  # `:type_ref`s to `kind: :map` definitions in `manifest.types`.
  # Manifests are compiled with `Module.create/3` under fixed names.
  use ExUnit.Case, async: false

  alias Ash.Info.Manifest
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.CustomTypeDecorationTest, as: T

  defmodule MapStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  defmodule Swatch do
    @moduledoc false
    # Declared only by a manifest `map` entry, whose fields' `client_name`s are
    # the only names it takes: `typescript_field_names/0` isn't read.
    use MapStorage

    def typescript_field_names, do: [hex: "colour", display_name: "ignored"]
  end

  defmodule Pair do
    @moduledoc false
    # Declared by `composite_types/1`.
    use MapStorage

    @impl true
    def composite?(_), do: true
    @impl true
    def composite_types(_), do: [{:left, :integer, []}, {:right, :integer, []}]
  end

  defmodule NewMoney do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshMoney.Types.Money
  end

  defp compile_manifest!(name, opts, body \\ nil) do
    module = Module.concat(T, name)

    ExUnit.CaptureIO.with_io(:stderr, fn ->
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
    end)

    AshTypescript.manifest(module)
  end

  defp definition(%Manifest{types: types}, module),
    do: Enum.find(types, &(&1.module == module))

  defp swatch_section do
    quote do
      custom_types do
        map AshTypescript.Manifest.CustomTypeDecorationTest.Swatch do
          field :hex, :string, allow_nil?: false
          field :display_name, :string, client_name: "label"
        end
      end
    end
  end

  # Compiled once for the route tests.
  defp routes_manifest do
    module = Module.concat(T, RoutesManifest)

    if Code.ensure_loaded?(module) do
      AshTypescript.manifest(module)
    else
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule Session do
          @moduledoc false
          use AshTypescript.TypedController

          typed_controller do
            module_name AshTypescript.Manifest.CustomTypeDecorationTest.Controller

            get :price do
              returns AshMoney.Types.Money
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            end

            get :new_price do
              returns AshTypescript.Manifest.CustomTypeDecorationTest.NewMoney
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            end

            post :paint do
              argument :swatch, AshTypescript.Manifest.CustomTypeDecorationTest.Swatch
              returns AshTypescript.Manifest.CustomTypeDecorationTest.Pair
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            end
          end
        end
      end)

      compile_manifest!(RoutesManifest, [typed_controllers: [T.Session]], swatch_section())
    end
  end

  describe "typed controller routes" do
    setup do
      %{manifest: routes_manifest()}
    end

    test "a route returning Money returns a type_ref to the built-in's definition", %{
      manifest: manifest
    } do
      route = Custom.route(manifest, T.Session, :price)
      assert %Manifest.Type{kind: :type_ref, module: AshMoney.Types.Money} = route.returns

      assert %Manifest.Type{kind: :map, fields: fields} =
               money = definition(manifest, AshMoney.Types.Money)

      assert AshRpc.Manifest.Custom.custom_type?(money)
      assert Enum.map(fields, & &1.name) == [:currency, :amount]
    end

    test "a route returning a NewType over Money returns a type_ref to its inherited definition",
         %{manifest: manifest} do
      route = Custom.route(manifest, T.Session, :new_price)
      assert %Manifest.Type{kind: :type_ref, module: T.NewMoney} = route.returns

      assert %Manifest.Type{kind: :map, fields: fields} =
               new_money = definition(manifest, T.NewMoney)

      assert AshRpc.Manifest.Custom.custom_type?(new_money)
      assert Enum.map(fields, & &1.name) == [:currency, :amount]
    end

    test "a route argument declared by a manifest map entry is a type_ref named by the entry alone",
         %{manifest: manifest} do
      route = Custom.route(manifest, T.Session, :paint)
      [%{name: :swatch, type: type}] = route.inputs
      assert %Manifest.Type{kind: :type_ref, module: T.Swatch} = type

      swatch = definition(manifest, T.Swatch)
      assert %Manifest.Type{kind: :map} = swatch
      assert AshRpc.Manifest.Custom.custom_type?(swatch)

      assert AshRpc.Manifest.Custom.type_field_names(swatch) == %{
               hex: "hex",
               display_name: "label"
             }
    end

    test "two fields of a manifest map entry with the same client_name are a name collision" do
      body =
        quote do
          custom_types do
            map AshTypescript.Manifest.CustomTypeDecorationTest.Swatch do
              field :hex, :string, client_name: "tone"
              field :display_name, :string, client_name: "tone"
            end
          end
        end

      # ash_rpc's NameCollisionError, wrapped by Spark for the transformer.
      error =
        assert_raise RuntimeError, fn ->
          compile_manifest!(CollidingManifest, [typed_controllers: [T.Session]], body)
        end

      assert Exception.message(error) =~
               ~s{Client name collision in type "Swatch" (AshTypescript.Manifest.CustomTypeDecorationTest.Swatch): :display_name and :hex both map to "tone"}
    end

    test "a route returning a composite type returns a type_ref", %{manifest: manifest} do
      route = Custom.route(manifest, T.Session, :paint)
      assert %Manifest.Type{kind: :type_ref, module: T.Pair} = route.returns
      assert %Manifest.Type{kind: :map} = definition(manifest, T.Pair)
    end
  end

  describe "typed channel publications" do
    test "a publication returning a composite type returns a type_ref" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule PairFeed do
          @moduledoc false
          use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

          pub_sub do
            module AshTypescript.Test.TestEndpoint
            prefix "pair_feed"

            publish :create, [:id],
              event: "pair_pushed",
              public?: true,
              returns: AshTypescript.Manifest.CustomTypeDecorationTest.Pair,
              transform: fn _ -> nil end
          end

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read, :create]
          end
        end

        defmodule PairFeedChannel do
          @moduledoc false
          use Phoenix.Channel
          use AshTypescript.TypedChannel

          typed_channel do
            topic "pair_feed:*"

            resource AshTypescript.Manifest.CustomTypeDecorationTest.PairFeed do
              publish :pair_pushed
            end
          end

          def join(_topic, _payload, socket), do: {:ok, socket}
        end
      end)

      manifest = compile_manifest!(PublicationManifest, typed_channels: [T.PairFeedChannel])

      publication = Custom.publication(manifest, T.PairFeedChannel, T.PairFeed, "pair_pushed")
      assert %Manifest.Type{kind: :type_ref, module: T.Pair} = publication.returns
      assert %Manifest.Type{kind: :map} = definition(manifest, T.Pair)
    end
  end

  describe "RPC resources" do
    test "an attribute declared by a manifest map entry is a type_ref with its client names" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule Canvas do
          @moduledoc false
          use Ash.Resource,
            domain: AshTypescript.Manifest.CustomTypeDecorationTest.CanvasDomain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "Canvas"
          end

          attributes do
            uuid_primary_key :id, public?: true

            attribute :swatch, AshTypescript.Manifest.CustomTypeDecorationTest.Swatch,
              public?: true
          end

          actions do
            defaults [:read]
          end
        end

        defmodule CanvasDomain do
          @moduledoc false
          use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTypescript.Rpc]

          typescript_rpc do
            resource AshTypescript.Manifest.CustomTypeDecorationTest.Canvas do
              rpc_action :list_canvases, :read
            end
          end

          resources do
            resource AshTypescript.Manifest.CustomTypeDecorationTest.Canvas
          end
        end
      end)

      manifest = compile_manifest!(CanvasManifest, [domains: [T.CanvasDomain]], swatch_section())

      %Manifest.Resource{fields: fields} = Enum.find(manifest.resources, &(&1.module == T.Canvas))
      assert %Manifest.Type{kind: :type_ref, module: T.Swatch} = fields[:swatch].type

      swatch = definition(manifest, T.Swatch)

      assert AshRpc.Manifest.Custom.type_field_names(swatch) == %{
               hex: "hex",
               display_name: "label"
             }
    end
  end
end
