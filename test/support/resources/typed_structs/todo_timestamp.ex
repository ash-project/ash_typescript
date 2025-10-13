# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TodoTimestamp do
  @moduledoc """
  Test TypedStruct for todo timestamp data.
  """
  use Ash.TypedStruct

  typed_struct do
    field(:created_by, :string, allow_nil?: false, description: "Test")
    field(:created_at, :utc_datetime, allow_nil?: false, description: "Test")
    field(:updated_by, :string, description: "Test")
    field(:updated_at, :utc_datetime, description: "Test")
  end
end
