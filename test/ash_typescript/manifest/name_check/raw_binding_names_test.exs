# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.NameCheck.RawBindingNamesTest do
  # The raw-name rule end to end: an rpc_action, typed query or route name
  # with a `?` or an underscore before a digit fails the manifest compile
  # with the name check's report, at path `[:names]`.
  use ExUnit.Case, async: true

  alias AshTypescript.Manifest.NameCheck.RawBindingNamesTest, as: T
  alias AshTypescript.Test.InlineManifest

  defmodule Res do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "RawBindingNamesRes"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read]
    end
  end

  defmodule ListOneDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheck.RawBindingNamesTest.Res do
        rpc_action :list_1, :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheck.RawBindingNamesTest.Res
    end
  end

  defmodule DoneDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheck.RawBindingNamesTest.Res do
        rpc_action :done?, :read
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheck.RawBindingNamesTest.Res
    end
  end

  defmodule DashOneDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Manifest.NameCheck.RawBindingNamesTest.Res do
        typed_query :dash_1, :read do
          ts_result_type_name "DashResult"
          fields [:id]
        end
      end
    end

    resources do
      resource AshTypescript.Manifest.NameCheck.RawBindingNamesTest.Res
    end
  end

  defmodule SaveOneController do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Test.RawBindingNamesSaveOneController

      post :save_1 do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
      end
    end
  end

  defmodule OkController do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Test.RawBindingNamesOkController

      post :ok? do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
      end
    end
  end

  defp compile_error(opts) do
    error = assert_raise RuntimeError, fn -> InlineManifest.build!(opts) end
    assert error.message =~ "Invalid generated names found."
    error.message
  end

  test "rpc_action :list_1" do
    message = compile_error(domains: [T.ListOneDomain])

    assert message =~
             ~s[  RPC action :list_1 in #{inspect(T.ListOneDomain)}:\n] <>
               "    - name :list_1, a question mark or an underscore before a digit: " <>
               "rename the rpc_action, e.g. :list1\n"
  end

  # A `?` also makes the bare name no identifier, which the line reports
  # first.
  test "rpc_action :done?" do
    message = compile_error(domains: [T.DoneDomain])

    assert message =~
             ~s[  RPC action :done? in #{inspect(T.DoneDomain)}:\n] <>
               ~s[    - function "done?" (and 12 derived names), not an identifier: ] <>
               "rename the rpc_action, e.g. :done\n"
  end

  test "typed_query :dash_1" do
    message = compile_error(domains: [T.DashOneDomain])

    assert message =~
             ~s[  Typed query :dash_1 in #{inspect(T.DashOneDomain)}:\n] <>
               "    - name :dash_1, a question mark or an underscore before a digit: " <>
               "rename the typed_query, e.g. :dash1\n"
  end

  test "route :save_1" do
    message = compile_error(typed_controllers: [T.SaveOneController])

    assert message =~
             ~s[  Route :save_1 of #{inspect(T.SaveOneController)}:\n] <>
               "    - name :save_1, a question mark or an underscore before a digit: " <>
               "rename the route, e.g. :save1\n"
  end

  test "route :ok?" do
    message = compile_error(typed_controllers: [T.OkController])

    assert message =~
             ~s[  Route :ok? of #{inspect(T.OkController)}:\n] <>
               ~s[    - function "ok?" (and 3 derived names), not an identifier: ] <>
               "rename the route, e.g. :ok\n"
  end

  test "the DslError path is [:names]" do
    message = compile_error(domains: [T.ListOneDomain])
    module = InlineManifest.module_for(domains: [T.ListOneDomain])

    assert message =~ "[#{inspect(module)}]\nnames :\n  Invalid generated names found."
  end
end
