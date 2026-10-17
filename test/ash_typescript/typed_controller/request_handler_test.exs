# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.RequestHandlerTest do
  # async: false — still mutates :typed_controller_show_raised_errors and
  # :typed_controller_error_handler (formatters come from redecorated manifests).
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  # Snapshot the global config this module mutates so it cannot leak into
  # later test modules.
  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :typed_controller_error_handler,
      :typed_controller_show_raised_errors
    ])

    base = manifest()

    %{
      manifests: %{
        pascal_out: AshTypescript.Manifest.redecorate(base, output_formatter: :pascal_case),
        uppercase_out:
          AshTypescript.Manifest.redecorate(base,
            output_formatter: {AshTypescript.Test.Formatters, :uppercase_format}
          )
      }
    }
  end

  alias AshTypescript.TypedController.RequestHandler

  # Dedicated controller for the `one_of` allowlist vector — kept out of the
  # shared test Session (and the codegen config) so it never touches generated
  # snapshots, only the runtime constraint-enforcement path.
  defmodule AllowlistSession do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.RequestHandlerTest.AllowlistController

      post :grant do
        run fn conn, params ->
          Plug.Conn.send_resp(conn, 200, "role=#{params.role}")
        end

        argument :role, :atom, allow_nil?: false, constraints: [one_of: [:viewer, :editor]]
      end
    end
  end

  # A handler that falls through with an {:error, secret-bearing struct}
  # instead of a conn — the unexpected-return path must not echo the term
  # to the client unless show_raised_errors is enabled (CVE-3218).
  defmodule LeakyUser do
    defstruct [:id, :hashed_password]
  end

  defmodule BadReturnSession do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.RequestHandlerTest.BadReturnController

      get :bad_return do
        run fn _conn, _params ->
          {:error,
           %AshTypescript.TypedController.RequestHandlerTest.LeakyUser{
             id: "usr_1",
             hashed_password: "$2b$12$SECRETHASH"
           }}
        end
      end
    end
  end

  # Declares an argument literally named `action` so a test can observe whether
  # a reserved key sneaks back in through a case/style variant (`Action`).
  defmodule ReservedSession do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.RequestHandlerTest.ReservedController

      get :reserved_echo do
        run fn conn, params ->
          Plug.Conn.send_resp(conn, 200, "action=#{inspect(Map.get(params, :action))}")
        end

        argument :action, :string, allow_nil?: true
      end
    end
  end

  # Arguments and results whose client-facing names depend on the configured
  # formatters and on `typescript_field_names` mappings. Kept out of the shared
  # Session so the generated snapshots are unaffected.
  defmodule FormattingSession do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.RequestHandlerTest.FormattingController

      post :echo do
        # The exact Elixir terms the handler received, for exact assertions
        run fn conn, params -> Plug.Conn.send_resp(conn, 200, :erlang.term_to_binary(params)) end

        argument :user_id, :string
        argument :display_name, :string
        argument :metadata, AshTypescript.Test.CustomMetadata
        argument :summary, AshTypescript.Test.RouteResultSummary
        argument :notes, :map
        argument :settings, AshTypescript.Test.RouteSettings
      end

      post :reply do
        returns :map

        constraints fields: [
                      user_id: [type: :string, allow_nil?: false],
                      metadata: [type: AshTypescript.Test.CustomMetadata],
                      items: [
                        type: {:array, :map},
                        constraints: [items: [fields: [tag_name: [type: :string]]]]
                      ]
                    ]

        run fn conn, _params ->
          AshTypescript.TypedController.json(conn, %{
            user_id: "u1",
            metadata: %{field_1: "a", is_active?: true, line_2: nil},
            items: [%{tag_name: "x"}]
          })
        end
      end

      post :reply_without_returns do
        run fn conn, _params -> AshTypescript.TypedController.json(conn, %{a: 1}) end
      end

      # A required multi-word argument, for errors that name it by client name
      post :require_user do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :user_id, :string, allow_nil?: false
      end
    end
  end

  # The test-local typed controllers are in no manifest module option (adding
  # them would change the generated snapshots), so requests run against an
  # inline manifest that lists them.
  @typed_controllers [
    AshTypescript.Test.Session,
    __MODULE__.AllowlistSession,
    __MODULE__.BadReturnSession,
    __MODULE__.ReservedSession,
    __MODULE__.FormattingSession
  ]

  defp manifest,
    do:
      AshTypescript.Test.InlineManifest.build!(
        typed_controllers: @typed_controllers,
        typed_channels: []
      )

  defp echoed(conn) do
    assert conn.status == 200, "expected 200, got #{conn.status}: #{conn.resp_body}"
    :erlang.binary_to_term(conn.resp_body)
  end

  defp put_env(key, value) do
    prev = Application.get_env(:ash_typescript, key)
    Application.put_env(:ash_typescript, key, value)
    on_exit(fn -> reset_env(key, prev) end)
  end

  # Builds the conn the way Phoenix would hand it to the controller. Body params
  # keep their JSON types, `path:` becomes conn.path_params, `query:` is
  # encoded into the URI, and `params` is their merge (path wins, like Phoenix).
  # The handler resolves keys per source, so tests must say where a key comes from.
  defp request(source_module, action, opts) do
    body = Keyword.get(opts, :body, %{})
    query = Keyword.get(opts, :query)
    uri = if query, do: "/test?" <> Plug.Conn.Query.encode(query), else: "/test"

    conn =
      Plug.Test.conn(:post, uri, body)
      |> Map.put(:path_params, Keyword.get(opts, :path, %{}))
      |> Plug.Conn.fetch_query_params()

    params = conn.query_params |> Map.merge(conn.body_params) |> Map.merge(conn.path_params)

    AshTypescript.with_manifest(Keyword.get_lazy(opts, :manifest, &manifest/0), fn ->
      RequestHandler.handle(conn, source_module, action, params)
    end)
  end

  defp call(action, params) when is_atom(action),
    do: request(AshTypescript.Test.Session, action, body: params)

  defp call(source_module, action, params), do: request(source_module, action, body: params)

  defp json_body(conn) do
    conn.resp_body |> Jason.decode!()
  end

  # Errors use the RPC error shape, so the affected argument is in `fields`
  # (a list) rather than a singular `field` key.
  defp error_for(conn, field) when is_binary(field) do
    conn |> json_body() |> Map.fetch!("errors") |> Enum.find(&(field in &1["fields"]))
  end

  defp error_fields(conn) do
    conn |> json_body() |> Map.fetch!("errors") |> Enum.flat_map(& &1["fields"])
  end

  describe "argument extraction — only declared arguments are passed to handler" do
    test "undeclared params are dropped" do
      conn = call(:echo_params, %{"name" => "alice", "extra_field" => "ignored"})

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      assert Map.has_key?(params, "name")
      refute Map.has_key?(params, "extra_field")
    end

    test "Phoenix internal params (_format, action, controller) are dropped" do
      conn =
        call(:echo_params, %{
          "name" => "alice",
          "_format" => "json",
          "action" => "echo_params",
          "controller" => "Elixir.SomeController"
        })

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      refute Map.has_key?(params, "_format")
      refute Map.has_key?(params, "action")
      refute Map.has_key?(params, "controller")
    end

    test "underscore-prefixed params are dropped" do
      conn = call(:echo_params, %{"name" => "alice", "_csrf_token" => "tok123"})

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      refute Map.has_key?(params, "_csrf_token")
    end

    test "route with no arguments receives empty map" do
      conn = call(:logout, %{"unexpected" => "param"})

      assert conn.status == 200
      assert conn.resp_body == "LoggedOut"
    end

    test "handler receives params with atom keys" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "5"})

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      # Keys were atoms in the handler, serialized to strings by Jason
      assert Map.has_key?(params, "name")
      assert Map.has_key?(params, "count")
    end
  end

  describe "required argument validation (allow_nil?: false)" do
    test "returns 422 when required argument is missing" do
      conn = call(:login, %{})

      assert conn.status == 422
      assert is_list(json_body(conn)["errors"])

      assert %{
               "type" => "required",
               "message" => "is required",
               "shortMessage" => "Required field",
               "vars" => %{"field" => "code"},
               "fields" => ["code"],
               "path" => []
             } = error_for(conn, "code")
    end

    test "returns 422 with all missing required fields listed" do
      conn = call(:update_provider, %{})

      assert conn.status == 422
      assert "enabled" in error_fields(conn)
    end

    test "succeeds when required arguments are present" do
      conn = call(:login, %{"code" => "abc123"})

      assert conn.status == 200
      assert conn.resp_body == "LoggedIn"
    end

    test "succeeds when all required arguments are present with optional ones omitted" do
      conn = call(:update_provider, %{"provider" => "github", "enabled" => "true"})

      assert conn.status == 200
      assert conn.resp_body == "ProviderUpdated"
    end
  end

  describe "Ash.Type.cast_input type casting" do
    test "casts string type" do
      conn = call(:echo_params, %{"name" => "alice"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["name"] == "alice"
    end

    test "casts integer from string" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "42"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == 42
    end

    test "casts integer from actual integer" do
      conn = call(:echo_params, %{"name" => "alice", "count" => 7})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == 7
    end

    test "returns 422 for invalid integer value" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "not_a_number"})

      assert conn.status == 422

      error = error_for(conn, "count")
      assert error["type"] == "invalid_argument"
      assert error["shortMessage"] == "Invalid argument"
      assert error["message"] =~ "invalid"
    end

    test "casts boolean from string 'true'" do
      conn = call(:echo_params, %{"name" => "alice", "active" => "true"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["active"] == true
    end

    test "casts boolean from string 'false'" do
      conn = call(:echo_params, %{"name" => "alice", "active" => "false"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["active"] == false
    end

    test "casts boolean from actual boolean" do
      conn = call(:echo_params, %{"name" => "alice", "active" => true})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["active"] == true
    end

    test "returns 422 for invalid boolean value" do
      conn = call(:update_provider, %{"enabled" => "not_a_bool"})

      assert conn.status == 422

      error = error_for(conn, "enabled")
      assert error["type"] == "invalid_argument"
      assert error["message"] =~ "invalid"
    end
  end

  describe "camelCase → snake_case normalization" do
    test "camelCase param keys are normalized to snake_case" do
      conn = call(:login, %{"code" => "abc", "rememberMe" => "true"})

      assert conn.status == 200
    end

    test "a non-client spelling of a body key is dropped" do
      assert echoed(call(FormattingSession, :echo, %{"display_name" => "Alice"})).display_name ==
               nil
    end

    test "camelCase required field is resolved after normalization" do
      conn = call(:echo_params, %{"name" => "alice", "displayName" => "Alice"})

      # displayName should be normalized but it's not a declared arg on echo_params,
      # so it should be dropped (only name, count, active are declared)
      assert conn.status == 200
      body = json_body(conn)
      refute Map.has_key?(body["params"], "display_name")
      refute Map.has_key?(body["params"], "displayName")
    end
  end

  describe "input field formatting" do
    test "nested keys of an argument type with typescript_field_names are mapped back" do
      params =
        call(FormattingSession, :echo, %{
          "metadata" => %{"field1" => "a", "isActive" => true, "line2" => "b"}
        })
        |> echoed()

      assert params.metadata == %{field_1: "a", is_active?: true, line_2: "b"}
    end

    test "mappings of a named type referenced only by routes are reversed" do
      # RouteSettings is reachable only from routes; the manifest carries it as a route-only type
      params =
        call(FormattingSession, :echo, %{"settings" => %{"enabled" => true, "level1" => 2}})
        |> echoed()

      assert params.settings == %{enabled?: true, level_1: 2}
    end

    test "nested typed map keys resolve by client name" do
      params =
        call(FormattingSession, :echo, %{"summary" => %{"totalCount" => 3, "status" => "ok"}})
        |> echoed()

      assert params.summary.total_count == 3
      assert params.summary.status == :ok
    end

    test "untyped map arguments are passed through as sent" do
      params = call(FormattingSession, :echo, %{"notes" => %{"someKey" => 1}}) |> echoed()

      assert params.notes == %{"someKey" => 1}
    end

    test "top-level keys match the client names generated by a custom output_field_formatter",
         %{manifests: m} do
      params =
        request(FormattingSession, :echo,
          body: %{"DISPLAY_NAME" => "Alice"},
          manifest: m.uppercase_out
        )
        |> echoed()

      assert params.display_name == "Alice"
    end

    test "pascal_case formatters are honored end to end", %{manifests: m} do
      params =
        request(FormattingSession, :echo,
          body: %{
            "DisplayName" => "Alice",
            "Summary" => %{"TotalCount" => 2, "Status" => "ok"}
          },
          manifest: m.pascal_out
        )
        |> echoed()

      assert params.display_name == "Alice"
      assert params.summary.total_count == 2
    end
  end

  describe "AshTypescript.TypedController.json/2" do
    test "formats the result against the route's returns type with the output formatter" do
      conn = call(FormattingSession, :reply, %{})

      assert conn.status == 200
      assert ["application/json" <> _] = Plug.Conn.get_resp_header(conn, "content-type")

      assert json_body(conn) == %{
               "userId" => "u1",
               "metadata" => %{"field1" => "a", "isActive" => true, "line2" => nil},
               "items" => [%{"tagName" => "x"}]
             }
    end

    test "honors a non-default output formatter", %{manifests: m} do
      body = request(FormattingSession, :reply, manifest: m.pascal_out) |> json_body()

      assert body["UserId"] == "u1"
      assert body["Items"] == [%{"TagName" => "x"}]
      # ValueFormatter emits typescript_field_names mappings as-is, unformatted
      assert body["Metadata"]["isActive"] == true
    end

    test "format_result/2 formats against the manifest route, not the DSL route" do
      route = AshTypescript.Manifest.Custom.route(manifest(), FormattingSession, :reply)

      conn =
        Plug.Test.conn(:post, "/test", %{})
        |> Plug.Conn.put_private(:ash_typescript_manifest_route, route)
        |> Plug.Conn.put_private(:ash_typescript_route, %{returns: :map, name: :reply})

      result =
        AshTypescript.with_manifest(manifest(), fn ->
          AshTypescript.TypedController.format_result(conn, %{
            user_id: "u1",
            metadata: %{field_1: "a", is_active?: true, line_2: nil},
            items: [%{tag_name: "x"}]
          })
        end)

      assert result == %{
               "userId" => "u1",
               "metadata" => %{"field1" => "a", "isActive" => true, "line2" => nil},
               "items" => [%{"tagName" => "x"}]
             }
    end

    test "raises (and so fails the request) on a route without returns" do
      put_env(:typed_controller_show_raised_errors, true)

      conn = call(FormattingSession, :reply_without_returns, %{})

      assert conn.status == 500
      assert conn.resp_body =~ "does not declare `returns`"
    end
  end

  describe "parameter collision (CVE-3217)" do
    # The IDOR vector: the trusted path param `provider` plus an appended
    # `?provider=<victim>` both reach one argument. We can't tell which the
    # caller meant, so the request is a 422 rather than a silent pick.
    test "a one-word name in both path and query is ambiguous" do
      conn =
        request(AshTypescript.Test.Session, :provider_page,
          path: %{"provider" => "github"},
          query: %{"provider" => "evil"}
        )

      assert conn.status == 422

      assert %{"errors" => [%{"type" => "ambiguous_param", "fields" => ["provider"]}]} =
               json_body(conn)
    end

    test "the same client key in query and body is ambiguous, and other arguments are still checked" do
      conn =
        request(AshTypescript.Test.Session, :echo_params,
          query: %{"count" => "1"},
          body: %{"count" => "2"}
        )

      assert conn.status == 422

      types =
        conn |> json_body() |> Map.fetch!("errors") |> Enum.map(&{&1["type"], &1["fields"]})

      assert {"ambiguous_param", ["count"]} in types
      assert {"required", ["name"]} in types
    end

    test "distinct keys that do not collide still succeed" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "5"})

      assert conn.status == 200
    end

    test "reserved keys are dropped after normalization, not before" do
      # `Action` folds to `action`. The reserved-key filter runs after
      # normalization, so it cannot be re-injected via a case variant.
      before = call(ReservedSession, :reserved_echo, %{"Action" => "evil"})

      assert before.status == 200
      assert before.resp_body == "action=nil"

      # The client name itself is reserved, so `action` never reaches the handler
      reserved = request(ReservedSession, :reserved_echo, query: %{"action" => "evil"})

      assert reserved.status == 200
      assert reserved.resp_body == "action=nil"
    end
  end

  describe "key resolution per source" do
    test "path params resolve by segment name" do
      conn =
        request(AshTypescript.Test.Session, :provider_page, path: %{"provider" => "github"})

      assert conn.status == 200
    end

    test "body and query keys resolve by client name" do
      assert %{user_id: "from-body"} =
               request(FormattingSession, :echo, body: %{"userId" => "from-body"}) |> echoed()

      assert %{display_name: "q"} =
               request(FormattingSession, :echo, query: %{"displayName" => "q"}) |> echoed()
    end

    test "a path param resolves under its segment name" do
      assert %{user_id: "from-path"} =
               request(FormattingSession, :echo, path: %{"user_id" => "from-path"}) |> echoed()
    end

    test "a query param spelled like a segment name is dropped (?user_id=)" do
      assert %{user_id: nil} =
               request(FormattingSession, :echo, query: %{"user_id" => "victim-999"})
               |> echoed()
    end

    test "undeclared, reserved and underscore-prefixed keys are dropped" do
      params =
        request(FormattingSession, :echo,
          body: %{"nope" => 1, "_csrf" => "x", "controller" => "y", "displayName" => "A"}
        )
        |> echoed()

      assert params.display_name == "A"
      refute Map.has_key?(params, :nope)
    end
  end

  describe "errors name multi-word arguments by client name" do
    test "required" do
      conn = call(FormattingSession, :require_user, %{})

      assert conn.status == 422

      assert %{
               "errors" => [
                 %{"type" => "required", "fields" => ["userId"], "vars" => %{"field" => "userId"}}
               ]
             } = json_body(conn)
    end

    test "invalid_argument" do
      conn =
        call(:register, %{
          "username" => "alice",
          "email" => "a@b.co",
          "age" => 20,
          "inviteCode" => "short"
        })

      assert conn.status == 422
      assert %{"type" => "invalid_argument"} = error_for(conn, "inviteCode")
    end

    test "ambiguous_param" do
      conn =
        request(FormattingSession, :echo,
          path: %{"user_id" => "from-path"},
          body: %{"userId" => "from-body"}
        )

      assert conn.status == 422

      assert %{"errors" => [%{"type" => "ambiguous_param", "fields" => ["userId"]}]} =
               json_body(conn)
    end
  end

  describe "nested unknown input" do
    test "nested misses are unknown_input with the argument's client name in the path" do
      conn =
        call(FormattingSession, :echo, %{
          "summary" => %{"total_count" => 3, "status" => "ok"},
          "metadata" => %{"field_1" => "a", "isActive" => true}
        })

      assert conn.status == 422
      errors = json_body(conn)["errors"]

      assert %{
               "type" => "unknown_input",
               "fields" => ["total_count"],
               "path" => ["summary"],
               "vars" => %{"field" => "total_count"},
               "shortMessage" => "Unknown input"
             } = Enum.find(errors, &(&1["fields"] == ["total_count"]))

      assert Enum.find(errors, &(&1["fields"] == ["field_1"]))["path"] == ["metadata"]
    end

    test "nested misses are reported in one 422 together with required and invalid_argument errors" do
      # create_task: title is required, metadata is TaskMetadata (an exposed
      # embedded resource, so strict), priority is an integer
      conn = call(:create_task, %{"metadata" => %{"bogus" => 1}, "priority" => "not_a_number"})

      assert conn.status == 422
      errors = json_body(conn)["errors"]
      by_type = Enum.group_by(errors, & &1["type"], & &1["fields"])

      assert ["title"] in by_type["required"]
      assert ["priority"] in by_type["invalid_argument"]
      assert %{"path" => ["metadata"]} = Enum.find(errors, &(&1["fields"] == ["bogus"]))
    end
  end

  describe "route missing from the manifest" do
    test "returns 500, with detail only when show_raised_errors? is on" do
      put_env(:typed_controller_show_raised_errors, false)
      default = AshTypescript.manifest(AshTypescript.Test.Manifest)

      conn = request(FormattingSession, :echo, manifest: default)
      assert conn.status == 500
      assert hd(json_body(conn)["errors"])["message"] == "Internal server error"

      put_env(:typed_controller_show_raised_errors, true)
      conn = request(FormattingSession, :echo, manifest: default)
      assert hd(json_body(conn)["errors"])["message"] =~ "`typed_controllers:` option"
    end
  end

  describe "optional arguments" do
    test "optional argument defaults to nil when omitted" do
      conn = call(:echo_params, %{"name" => "alice"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == nil
      assert body["params"]["active"] == nil
    end

    test "optional argument is passed through when provided" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "3", "active" => "true"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == 3
      assert body["params"]["active"] == true
    end

    test "route with all optional arguments works when none provided" do
      conn = call(:provider_page, %{"provider" => "github"})

      assert conn.status == 200
      assert conn.resp_body == "ProviderPage"
    end

    test "search route requires q argument" do
      conn = call(:search, %{})

      assert conn.status == 422
      assert "q" in error_fields(conn)
    end

    test "search route succeeds with required q argument" do
      conn = call(:search, %{"q" => "test"})

      assert conn.status == 200
      assert conn.resp_body == "Search"
    end
  end

  describe "handler dispatch" do
    test "handler receives Plug.Conn and returns Plug.Conn" do
      conn = call(:auth, %{})

      assert %Plug.Conn{} = conn
      assert conn.status == 200
      assert conn.resp_body == "Auth"
    end

    test "handler receives only declared arguments in params map" do
      conn =
        call(:echo_params, %{
          "name" => "alice",
          "count" => "10",
          "undeclared" => "dropped",
          "_meta" => "dropped"
        })

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      assert params["name"] == "alice"
      assert params["count"] == 10
      # undeclared and underscore-prefixed params are not passed to handler
      refute Map.has_key?(params, "undeclared")
      refute Map.has_key?(params, "_meta")
    end
  end

  describe "error responses" do
    test "422 response has errors array" do
      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)
      assert is_list(body["errors"])
      assert body["errors"] != []
    end

    test "each error carries the full RPC error shape" do
      conn = call(:login, %{})

      for error <- json_body(conn)["errors"] do
        assert is_binary(error["type"])
        assert is_binary(error["message"])
        assert is_binary(error["shortMessage"])
        assert is_map(error["vars"])
        assert is_list(error["fields"])
        assert is_list(error["path"])
      end
    end

    test "error keys respect the configured output_field_formatter", %{manifests: m} do
      conn = request(AshTypescript.Test.Session, :login, manifest: m.pascal_out)

      assert %{"Errors" => [%{"Type" => "required", "ShortMessage" => "Required field"} | _]} =
               json_body(conn)
    end

    test "cast errors and required errors can appear together" do
      conn = call(:echo_params, %{"count" => "not_a_number"})

      assert conn.status == 422

      fields_with_errors = error_fields(conn)
      # name is required and missing
      assert "name" in fields_with_errors
      # count has an invalid value
      assert "count" in fields_with_errors
    end
  end

  describe "error handler" do
    setup do
      prev = Application.get_env(:ash_typescript, :typed_controller_error_handler)
      on_exit(fn -> reset_env(:typed_controller_error_handler, prev) end)
      :ok
    end

    test "MFA error handler transforms 422 errors" do
      Application.put_env(
        :ash_typescript,
        :typed_controller_error_handler,
        {__MODULE__.TestErrorHandler, :handle, []}
      )

      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)

      Enum.each(body["errors"], fn error ->
        assert error["transformed"] == true
      end)
    end

    test "MFA error handler can filter out errors by returning nil" do
      Application.put_env(
        :ash_typescript,
        :typed_controller_error_handler,
        {__MODULE__.FilteringErrorHandler, :handle, []}
      )

      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)
      # FilteringErrorHandler returns nil for all errors
      assert body["errors"] == []
    end

    test "module error handler transforms errors" do
      Application.put_env(
        :ash_typescript,
        :typed_controller_error_handler,
        __MODULE__.ModuleErrorHandler
      )

      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)

      # Handlers run before formatting, so keys they add are formatted too.
      Enum.each(body["errors"], fn error ->
        assert error["moduleHandled"] == true
      end)
    end
  end

  describe "show_raised_errors?" do
    setup do
      prev = Application.get_env(:ash_typescript, :typed_controller_show_raised_errors)
      on_exit(fn -> reset_env(:typed_controller_show_raised_errors, prev) end)
      :ok
    end

    test "returns generic message when show_raised_errors is false (default)" do
      Application.put_env(:ash_typescript, :typed_controller_show_raised_errors, false)

      conn = call(:raise_error, %{})

      assert conn.status == 500
      body = json_body(conn)
      error = hd(body["errors"])
      assert error["message"] == "Internal server error"
    end

    test "returns actual message when show_raised_errors is true" do
      Application.put_env(:ash_typescript, :typed_controller_show_raised_errors, true)

      conn = call(:raise_error, %{})

      assert conn.status == 500
      body = json_body(conn)
      error = hd(body["errors"])
      assert error["message"] == "test error for show_raised_errors"
    end

    # CVE-3218: a non-conn handler return was inspected verbatim into the 500
    # body, leaking internal struct fields to an unauthenticated client.
    test "unexpected handler return is not echoed when show_raised_errors is false (CVE-3218)" do
      Application.put_env(:ash_typescript, :typed_controller_show_raised_errors, false)

      {conn, log} =
        ExUnit.CaptureLog.with_log(fn ->
          call(BadReturnSession, :bad_return, %{})
        end)

      assert conn.status == 500
      error = conn |> json_body() |> Map.fetch!("errors") |> hd()
      assert error["message"] == "Internal server error"
      refute conn.resp_body =~ "SECRETHASH"

      # The diagnostic still reaches the developer server-side.
      assert log =~ "Route handler must return %Plug.Conn{}"
      assert log =~ "SECRETHASH"
    end

    test "unexpected handler return is detailed when show_raised_errors is true" do
      Application.put_env(:ash_typescript, :typed_controller_show_raised_errors, true)

      {conn, _log} =
        ExUnit.CaptureLog.with_log(fn ->
          call(BadReturnSession, :bad_return, %{})
        end)

      assert conn.status == 500
      error = conn |> json_body() |> Map.fetch!("errors") |> hd()
      assert error["message"] =~ "Route handler must return %Plug.Conn{}"
      assert error["message"] =~ "SECRETHASH"
    end
  end

  defp reset_env(key, nil), do: Application.delete_env(:ash_typescript, key)
  defp reset_env(key, value), do: Application.put_env(:ash_typescript, key, value)

  defmodule TestErrorHandler do
    def handle(error, _context) do
      Map.put(error, :transformed, true)
    end
  end

  describe "constraint application (Ash action-argument semantics)" do
    # The handler mirrors Ash's action-argument pipeline: cast_input, then
    # apply_constraints, then re-check allow_nil?. Strings therefore get the
    # allow_empty?: false default — "" becomes nil — and declared constraints
    # are enforced. The generated route schemas mirror this (e.g. `.min(1)`
    # on required strings).
    test "empty string is rejected for an allow_nil?: false string argument" do
      conn = call(:login, %{"code" => ""})

      assert conn.status == 422

      assert %{"errors" => [%{"type" => "required", "fields" => ["code"]}]} = json_body(conn)
    end

    test "empty string becomes nil for a nilable string argument" do
      conn = call(:echo_params, %{"name" => "alice", "bio" => ""})

      assert conn.status == 200
      assert json_body(conn)["params"]["bio"] == nil
    end

    test "strings are trimmed per the trim? default" do
      conn = call(:echo_params, %{"name" => "  alice  "})

      assert conn.status == 200
      assert json_body(conn)["params"]["name"] == "alice"
    end

    test "array arguments cast and enforce item constraints" do
      conn = call(:search, %{"q" => "elixir", "tags" => ["ash", "spark"]})
      assert conn.status == 200

      # `tags` declares `items: [min_length: 2]`
      conn = call(:search, %{"q" => "elixir", "tags" => ["ash", "x"]})
      assert conn.status == 422
      assert [%{"fields" => ["tags"], "type" => "invalid_argument"}] = json_body(conn)["errors"]
    end

    test "array arguments accept an omitted value" do
      conn = call(:search, %{"q" => "elixir"})
      assert conn.status == 200
    end

    test "declared constraints are enforced" do
      conn = call(:register, %{"username" => "x", "email" => "a@b.co", "age" => 20})

      assert conn.status == 422

      # `min_length: 3` — the placeholder stays in `message` and the value
      # lands in `vars`, so the client interpolates (as with RPC errors).
      error = error_for(conn, "username")
      assert error["type"] == "invalid_argument"
      assert error["message"] =~ "%{min}"
      assert error["vars"]["min"] == 3
    end

    test "one_of allowlist rejects a value outside the declared set" do
      # The flagship CVE-3216 vector: an atom `one_of` allowlist gating a role.
      # `:admin` must already exist as an atom for this to exercise the
      # constraint rather than the cast's atom-existence check — as it would in
      # any real app with an `:admin` role. Reference the literal to intern it.
      _ = :admin
      conn = call(AllowlistSession, :grant, %{"role" => "admin"})

      # Without apply_constraints, cast_input(:atom, "admin", one_of: ...) returns
      # {:ok, :admin} and the handler runs privileged. The constraint check is
      # what turns this into a 422.
      assert conn.status == 422

      assert %{"errors" => [%{"type" => "invalid_argument", "fields" => ["role"]}]} =
               json_body(conn)
    end

    test "one_of allowlist accepts a value inside the declared set" do
      conn = call(AllowlistSession, :grant, %{"role" => "editor"})

      assert conn.status == 200
      assert conn.resp_body == "role=editor"
    end
  end

  defmodule FilteringErrorHandler do
    def handle(_error, _context), do: nil
  end

  defmodule ModuleErrorHandler do
    def handle_error(error, _context) do
      Map.put(error, :module_handled, true)
    end
  end
end
