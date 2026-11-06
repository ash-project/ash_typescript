# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Resources are defined at top level so Spark DSL fully compiles them before
# the inline domains reference them.

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest.Settings do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded, extensions: [AshTypescript.Resource]

  typescript do
    type_name "VerifyOptionsSettings"
  end

  attributes do
    attribute :theme, :string, public?: true
  end

  calculations do
    calculate :display_theme, :string, expr(theme), public?: true
  end
end

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest.Item do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "VerifyOptionsItem"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :source_id, :uuid, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest.Source do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "VerifyOptionsSource"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :settings, AshTypescript.Rpc.VerifyRpcOptionsTest.Settings, public?: true
  end

  relationships do
    has_many :items, AshTypescript.Rpc.VerifyRpcOptionsTest.Item,
      destination_attribute: :source_id,
      public?: true
  end

  calculations do
    calculate :display_name, :string, expr(name), public?: true
  end

  aggregates do
    count :items_count, :items, public?: true
  end

  actions do
    defaults [:read]

    read :read_with_meta do
      metadata :total_count, :integer
      metadata :cache_status, :string
    end
  end
end

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest do
  @moduledoc """
  Integration tests for the `show_metadata` and `allowed_loads`/`denied_loads`
  existence checks and the reserved-name check in
  `AshTypescript.Manifest.Verifiers.VerifyRpc`.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.VerifyRpcOptionsTest.{Item, Source}

  describe "show_metadata validation" do
    test "rejects metadata fields the action does not define" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule BadMetadataDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :list_with_meta, :read_with_meta,
                  show_metadata: [:total_count, :has_more]
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert {:error, message} = silent_verify_for_domains([domain])
      assert message =~ "show_metadata contains unknown metadata fields"
      assert message =~ ":has_more"
      assert message =~ "list_with_meta"
    end

    test "accepts metadata fields the action defines" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule GoodMetadataDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :list_with_meta_ok, :read_with_meta,
                  show_metadata: [:total_count, :cache_status]
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert :ok = silent_verify_for_domains([domain])
    end
  end

  describe "allowed_loads / denied_loads validation" do
    test "rejects load paths that don't exist on the resource" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule BadAllowedLoadsDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :list_bad_loads, :read, allowed_loads: [:nonexistent]
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert {:error, message} = silent_verify_for_domains([domain])
      assert message =~ "allowed_loads contains invalid load paths"
      assert message =~ "nonexistent"
    end

    test "rejects nested load paths that don't exist on the relationship destination" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule BadNestedDeniedLoadsDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :list_bad_nested, :read, denied_loads: [items: [:bogus]]
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert {:error, message} = silent_verify_for_domains([domain])
      assert message =~ "denied_loads contains invalid load paths"
      assert message =~ "items.bogus"
    end

    test "rejects plain attributes (never load paths)" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule AttributeLoadDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :list_attr_load, :read, allowed_loads: [:name]
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert {:error, message} = silent_verify_for_domains([domain])
      assert message =~ "allowed_loads contains invalid load paths"
      assert message =~ "name"
    end

    test "rejects unknown fields nested under an embedded attribute" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule BadEmbeddedLoadsDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :list_bad_embedded, :read, allowed_loads: [settings: [:nope]]
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert {:error, message} = silent_verify_for_domains([domain])
      assert message =~ "allowed_loads contains invalid load paths"
      assert message =~ "settings.nope"
    end

    test "accepts relationships, calculations, aggregates, and valid nested paths" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule GoodLoadsDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :list_good_loads, :read,
                  allowed_loads: [
                    :display_name,
                    :items_count,
                    settings: [:display_theme],
                    items: []
                  ]
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert :ok = silent_verify_for_domains([domain])
    end
  end

  describe "reserved RPC action names" do
    test "rejects an rpc_action whose function name is a reserved word" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule ReservedNameDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :delete, :read
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      error =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([domain])
        end

      assert Exception.message(error) =~
               "  RPC action :delete in #{inspect(domain)}:\n" <>
                 ~s[    - function "delete", a JavaScript reserved word: rename the rpc_action, ] <>
                 "for example :delete_item\n"
    end

    test "accepts names that contain a reserved word or are TypeScript type keywords" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule NearReservedNameDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                rpc_action :delete_item, :read
                rpc_action :import_users, :read
                rpc_action :string, :read
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert :ok = silent_verify_for_domains([domain])
    end

    test "rejects a typed_query whose fields const name is a reserved word" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule ReservedTypedQueryDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                typed_query :delete, :read do
                  ts_result_type_name "DeleteResult"
                  fields [:id]
                end

                typed_query :list_sources, :read do
                  ts_result_type_name "ListSourcesResult"
                  ts_fields_const_name "default"
                  fields [:id]
                end
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      error =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([domain])
        end

      message = Exception.message(error)

      assert message =~
               "  Typed query :delete in #{inspect(domain)}:\n" <>
                 ~s[    - const "delete", a JavaScript reserved word: rename the typed_query, ] <>
                 "for example :delete_item, or set ts_fields_const_name\n"

      assert message =~
               "  Typed query :list_sources in #{inspect(domain)}:\n" <>
                 ~s[    - const "default" (ts_fields_const_name), a JavaScript reserved word: ] <>
                 "change ts_fields_const_name\n"
    end

    test "accepts a reserved typed_query name with a valid ts_fields_const_name" do
      {domain, stderr} =
        define_quietly(fn ->
          defmodule RenamedTypedQueryDomain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource Source do
                typed_query :delete, :read do
                  ts_result_type_name "DeleteResult"
                  ts_fields_const_name "deleteFields"
                  fields [:id]
                end
              end
            end

            resources do
              resource Source
              resource Item
            end
          end
        end)

      refute stderr =~ "Exception while verifying"

      assert :ok = silent_verify_for_domains([domain])
    end
  end

  # Defines the inline domain inside a stderr capture, so the test can assert
  # its verifiers print nothing (a relationship destination missing from the
  # domain shows up as "Exception while verifying").
  defp define_quietly(define) do
    {{:module, domain, _binary, _term}, stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, define)

    {domain, stderr}
  end

  # Compiling the throwaway manifest module makes Elixir's parallel checker echo
  # raised DslErrors (and RPC config IO.warn output) to stderr, so silence it.
  defp silent_verify_for_domains(domains) do
    {result, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        AshTypescript.Manifest.verify_for_domains(domains)
      end)

    result
  end
end
