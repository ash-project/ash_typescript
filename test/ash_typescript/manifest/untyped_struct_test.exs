# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.UntypedStructTest do
  # Typed route arguments, route `returns`, publication `returns` and typed
  # queries that reach untyped structs (`:struct` without `fields`) or
  # undeclared map-like custom types are rejected when the manifest module
  # compiles. RPC actions are rejected by ash_rpc's decorator. Undeclared
  # custom types get the declaration hint, closed over the manifest's
  # `custom_types` entries.
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.UntypedStructTest, as: T

  defmodule PlainToken do
    @moduledoc false
    defstruct [:value]
  end

  defmodule PlainTokenPair do
    @moduledoc false
    # A composite custom type whose `token` entry is a plain struct.
    use Ash.Type

    @impl true
    def storage_type(_), do: :map
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
    @impl true
    def composite?(_), do: true
    @impl true
    def composite_types(_),
      do: [{:token, :struct, [instance_of: AshTypescript.Manifest.UntypedStructTest.PlainToken]}]
  end

  defmodule Blob do
    @moduledoc false
    # Map storage and no declared fields.
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

  defmodule NamedBlob do
    @moduledoc false
    # Map storage, no declared fields, and a TypeScript type name.
    use Ash.Type

    def typescript_type_name, do: "NamedBlob"

    @impl true
    def storage_type(_), do: :map
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  defp compile_manifest!(name, typed_controllers, typed_channels) do
    Module.create(
      Module.concat(T, name),
      quote do
        use AshTypescript.Manifest,
          otp_app: :ash_typescript,
          domains: [AshTypescript.Test.SecondDomain],
          typed_controllers: unquote(typed_controllers),
          typed_channels: unquote(typed_channels)
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp assert_rejected(name, typed_controllers, typed_channels) do
    error =
      assert_raise Spark.Error.DslError, fn ->
        ExUnit.CaptureIO.with_io(:stderr, fn ->
          compile_manifest!(name, typed_controllers, typed_channels)
        end)
      end

    Exception.message(error)
  end

  describe "typed controller routes" do
    test "an argument that is an untyped struct is rejected" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule ArgSession do
          @moduledoc false
          use AshTypescript.TypedController

          typed_controller do
            module_name AshTypescript.Manifest.UntypedStructTest.ArgController

            post :redeem do
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              argument :token, :struct, constraints: [instance_of: T.PlainToken]
            end
          end
        end
      end)

      message = assert_rejected(ArgManifest, [T.ArgSession], [])

      assert message =~
               "AshTypescript.Manifest.UntypedStructTest.ArgSession route :redeem accepts " <>
                 "an untyped struct, AshTypescript.Manifest.UntypedStructTest.PlainToken, " <>
                 "at argument :token."

      assert message =~ "* an Ash.TypedStruct"
    end

    test "an untyped struct nested in an argument is rejected at its path" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule NestedArgSession do
          @moduledoc false
          use AshTypescript.TypedController

          typed_controller do
            module_name AshTypescript.Manifest.UntypedStructTest.NestedArgController

            post :redeem_all do
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              argument :name, :string

              argument :tokens, {:array, :struct},
                constraints: [items: [instance_of: T.PlainToken]]
            end
          end
        end
      end)

      message = assert_rejected(NestedArgManifest, [T.NestedArgSession], [])

      assert message =~
               "route :redeem_all accepts an untyped struct, " <>
                 "AshTypescript.Manifest.UntypedStructTest.PlainToken, at argument :tokens → []."
    end

    test "a returns that is an untyped struct is rejected" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule ReturnsSession do
          @moduledoc false
          use AshTypescript.TypedController

          typed_controller do
            module_name AshTypescript.Manifest.UntypedStructTest.ReturnsController

            get :current_token do
              returns :struct
              constraints instance_of: T.PlainToken
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            end
          end
        end
      end)

      message = assert_rejected(ReturnsManifest, [T.ReturnsSession], [])

      assert message =~
               "AshTypescript.Manifest.UntypedStructTest.ReturnsSession route :current_token " <>
                 "returns an untyped struct, AshTypescript.Manifest.UntypedStructTest.PlainToken, " <>
                 "at returns."

      assert message =~ "* an Ash.TypedStruct"
    end

    test "a returns that is a composite type holding an untyped struct is rejected at its path" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule CompositeReturnsSession do
          @moduledoc false
          use AshTypescript.TypedController

          typed_controller do
            module_name AshTypescript.Manifest.UntypedStructTest.CompositeReturnsController

            get :token_pair do
              returns T.PlainTokenPair
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            end
          end
        end
      end)

      message = assert_rejected(CompositeReturnsManifest, [T.CompositeReturnsSession], [])

      assert message =~
               "AshTypescript.Manifest.UntypedStructTest.CompositeReturnsSession route :token_pair " <>
                 "returns an untyped struct, AshTypescript.Manifest.UntypedStructTest.PlainToken, " <>
                 "at returns → token."
    end
  end

  describe "typed channel publications" do
    test "a publication returns that is an untyped struct is rejected" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule TokenFeed do
          @moduledoc false
          use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

          pub_sub do
            module AshTypescript.Test.TestEndpoint
            prefix "token_feed"

            publish :create, [:id],
              event: "token_pushed",
              public?: true,
              returns: :struct,
              constraints: [instance_of: AshTypescript.Manifest.UntypedStructTest.PlainToken],
              transform: fn _ -> nil end
          end

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read, :create]
          end
        end

        defmodule TokenFeedChannel do
          @moduledoc false
          use Phoenix.Channel
          use AshTypescript.TypedChannel

          typed_channel do
            topic "token_feed:*"

            resource AshTypescript.Manifest.UntypedStructTest.TokenFeed do
              publish :token_pushed
            end
          end

          def join(_topic, _payload, socket), do: {:ok, socket}
        end
      end)

      message = assert_rejected(PublicationManifest, [], [T.TokenFeedChannel])

      assert message =~
               "AshTypescript.Manifest.UntypedStructTest.TokenFeedChannel publication " <>
                 ~s("token_pushed" of AshTypescript.Manifest.UntypedStructTest.TokenFeed ) <>
                 "returns an untyped struct, AshTypescript.Manifest.UntypedStructTest.PlainToken, " <>
                 "at returns."

      assert message =~ "* an Ash.TypedStruct"
    end
  end

  describe "typed queries" do
    # Typed queries are off-wire entrypoints (the mapping source returns nil
    # for them), so ash_rpc's decorator doesn't check them; the manifest
    # decoration runs ash_rpc's check for each one.
    defp assert_typed_query_rejected(domain) do
      error =
        assert_raise RuntimeError, fn ->
          ExUnit.CaptureIO.with_io(:stderr, fn ->
            AshTypescript.Manifest.verify_for_domains([domain])
          end)
        end

      Exception.message(error)
    end

    test "a field-reachable attribute that is an untyped struct is rejected" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule BlobProbe do
          @moduledoc false
          use Ash.Resource,
            domain: AshTypescript.Manifest.UntypedStructTest.BlobProbeDomain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "BlobProbe"
          end

          attributes do
            uuid_primary_key :id, public?: true
            attribute :blob, :struct, constraints: [instance_of: T.PlainToken], public?: true
          end

          actions do
            read :search
          end
        end

        defmodule BlobProbeDomain do
          @moduledoc false
          use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTypescript.Rpc]

          typescript_rpc do
            resource AshTypescript.Manifest.UntypedStructTest.BlobProbe do
              typed_query :probe_list, :search do
                ts_fields_const_name "probeList"
                ts_result_type_name "ProbeListResult"
                fields [:id, :blob]
              end
            end
          end

          resources do
            resource AshTypescript.Manifest.UntypedStructTest.BlobProbe
          end
        end
      end)

      message = assert_typed_query_rejected(T.BlobProbeDomain)

      assert message =~
               ~s[Entrypoint "probe_list" (AshTypescript.Manifest.UntypedStructTest.BlobProbe, ] <>
                 "action :search) returns an untyped struct, " <>
                 "AshTypescript.Manifest.UntypedStructTest.PlainToken, " <>
                 "at AshTypescript.Manifest.UntypedStructTest.BlobProbe records → blob."

      assert message =~ "* an Ash.TypedStruct"
    end

    test "an action argument that is an untyped struct is rejected" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule ArgProbe do
          @moduledoc false
          use Ash.Resource,
            domain: AshTypescript.Manifest.UntypedStructTest.ArgProbeDomain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "ArgProbe"
          end

          attributes do
            uuid_primary_key :id, public?: true
          end

          actions do
            read :search do
              argument :token, :struct, constraints: [instance_of: T.PlainToken]
            end
          end
        end

        defmodule ArgProbeDomain do
          @moduledoc false
          use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTypescript.Rpc]

          typescript_rpc do
            resource AshTypescript.Manifest.UntypedStructTest.ArgProbe do
              typed_query :probe_by_token, :search do
                ts_fields_const_name "probeByToken"
                ts_result_type_name "ProbeByTokenResult"
                fields [:id]
              end
            end
          end

          resources do
            resource AshTypescript.Manifest.UntypedStructTest.ArgProbe
          end
        end
      end)

      message = assert_typed_query_rejected(T.ArgProbeDomain)

      assert message =~
               ~s[Entrypoint "probe_by_token" (AshTypescript.Manifest.UntypedStructTest.ArgProbe, ] <>
                 "action :search) accepts an untyped struct, " <>
                 "AshTypescript.Manifest.UntypedStructTest.PlainToken, at argument :token."
    end
  end

  describe "undeclared map-like custom types" do
    @hint "Declare its fields with a `map` entry in your manifest module's `custom_types` " <>
            "section, a `typescript_fields/0` callback on the type, or " <>
            "`composite?/1` + `composite_types/1`."

    defp undeclared(module, at),
      do:
        "an undeclared custom type, #{inspect(module)}, at #{at}.\n\n" <>
          "Its values are maps or structs (`storage_type :map` / composite), but no fields " <>
          "are declared for it, so their keys have no client names.\n\n"

    defp compile_raising!(name, opts, body) do
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Module.create(
          Module.concat(T, name),
          quote do
            use AshTypescript.Manifest, unquote([otp_app: :ash_typescript] ++ opts)
            unquote(body)
          end,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    test "an RPC action gets the hint with the manifest's scalar declaration" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule BlobAction do
          @moduledoc false
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "BlobAction"
          end

          attributes do
            uuid_primary_key :id
          end

          actions do
            action :get_blob, T.Blob do
              run fn _input, _context -> {:ok, %{}} end
            end
          end
        end

        defmodule BlobActionDomain do
          @moduledoc false
          use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

          typescript_rpc do
            resource AshTypescript.Manifest.UntypedStructTest.BlobAction do
              rpc_action :get_blob, :get_blob
            end
          end

          resources do
            resource AshTypescript.Manifest.UntypedStructTest.BlobAction
          end
        end
      end)

      # Spark wraps the decorator's AshRpc.Manifest.UntypedStructError.
      error =
        assert_raise RuntimeError, fn ->
          compile_raising!(
            BlobActionManifest,
            [domains: [T.BlobActionDomain]],
            quote do
              custom_types do
                scalar AshTypescript.Manifest.UntypedStructTest.Blob, :string
              end
            end
          )
        end

      assert Exception.message(error) =~
               ~s[Entrypoint "get_blob" (#{inspect(T.BlobAction)}, action :get_blob) returns ] <>
                 undeclared(T.Blob, "returns") <>
                 @hint <>
                 " Remove the `scalar` declaration: a map-like type's TypeScript is " <>
                 "generated from its fields."
    end

    test "a typed query gets the hint" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule BlobQuery do
          @moduledoc false
          use Ash.Resource,
            domain: AshTypescript.Manifest.UntypedStructTest.BlobQueryDomain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "BlobQuery"
          end

          attributes do
            uuid_primary_key :id, public?: true
            attribute :blob, T.NamedBlob, public?: true
          end

          actions do
            read :search
          end
        end

        defmodule BlobQueryDomain do
          @moduledoc false
          use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTypescript.Rpc]

          typescript_rpc do
            resource AshTypescript.Manifest.UntypedStructTest.BlobQuery do
              typed_query :blob_list, :search do
                ts_fields_const_name "blobList"
                ts_result_type_name "BlobListResult"
                fields [:id, :blob]
              end
            end
          end

          resources do
            resource AshTypescript.Manifest.UntypedStructTest.BlobQuery
          end
        end
      end)

      message = assert_typed_query_rejected(T.BlobQueryDomain)

      assert message =~
               ~s[Entrypoint "blob_list" (#{inspect(T.BlobQuery)}, action :search) returns ] <>
                 undeclared(T.NamedBlob, "#{inspect(T.BlobQuery)} records → blob") <>
                 @hint <>
                 " Remove `typescript_type_name/0`: a map-like type's TypeScript is " <>
                 "generated from its fields."
    end

    test "a typed controller route gets the hint" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule BlobSession do
          @moduledoc false
          use AshTypescript.TypedController

          typed_controller do
            module_name AshTypescript.Manifest.UntypedStructTest.BlobController

            get :blob do
              returns T.NamedBlob
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            end
          end
        end
      end)

      message = assert_rejected(BlobRouteManifest, [T.BlobSession], [])

      assert message =~
               "#{inspect(T.BlobSession)} route :blob returns " <>
                 undeclared(T.NamedBlob, "returns") <>
                 @hint <>
                 " Remove `typescript_type_name/0`: a map-like type's TypeScript is " <>
                 "generated from its fields."
    end

    test "a typed channel publication gets the hint" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        defmodule BlobFeed do
          @moduledoc false
          use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

          pub_sub do
            module AshTypescript.Test.TestEndpoint
            prefix "blob_feed"

            publish :create, [:id],
              event: "blob_pushed",
              public?: true,
              returns: AshTypescript.Manifest.UntypedStructTest.Blob,
              transform: fn _ -> nil end
          end

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read, :create]
          end
        end

        defmodule BlobFeedChannel do
          @moduledoc false
          use Phoenix.Channel
          use AshTypescript.TypedChannel

          typed_channel do
            topic "blob_feed:*"

            resource AshTypescript.Manifest.UntypedStructTest.BlobFeed do
              publish :blob_pushed
            end
          end

          def join(_topic, _payload, socket), do: {:ok, socket}
        end
      end)

      message = assert_rejected(BlobPublicationManifest, [], [T.BlobFeedChannel])

      assert message =~
               "#{inspect(T.BlobFeedChannel)} publication " <>
                 ~s("blob_pushed" of #{inspect(T.BlobFeed)} returns ) <>
                 undeclared(T.Blob, "returns") <> @hint

      refute message =~ "Remove"
    end
  end

  test "the existing typed controllers and channels still compile" do
    assert %Ash.Info.Manifest{} =
             AshTypescript.Test.InlineManifest.build!(
               typed_controllers: [AshTypescript.Test.Session],
               typed_channels: [AshTypescript.Test.PublicationFixtures.FeedChannel]
             )
  end
end
