defmodule SlackDB.ChannelsTest do
  use ExUnit.Case

  import Mox
  import SlackDB.Channels

  @pagination_result_1 %{
    "channels" => [
      %{
        "id" => "CQ5H0JBDZ",
        "name" => "general"
      },
      %{
        "id" => "CQ5H0K15Z",
        "name" => "slackdb"
      }
    ],
    "ok" => true,
    "response_metadata" => %{"next_cursor" => "cursor1"}
  }

  @pagination_result_2 %{
    "channels" => [
      %{
        "id" => "CQ5H0JBDZ",
        "name" => "new"
      }
    ],
    "ok" => true,
    "response_metadata" => %{"next_cursor" => ""}
  }

  setup do
    Client.Mock
    |> expect(:conversations_list, 6, fn
      _, cursor: nil -> {:ok, @pagination_result_1}
      _, cursor: "cursor1" -> {:ok, @pagination_result_2}
    end)

    :ok
  end

  test "conversations_list" do
    assert get_all_convos("server") ===
             {:ok,
              [
                %{"id" => "CQ5H0JBDZ", "name" => "general"},
                %{"id" => "CQ5H0K15Z", "name" => "slackdb"},
                %{"id" => "CQ5H0JBDZ", "name" => "new"}
              ]}

    assert get_all_convos("doesnt exist") ===
             {:error, "KeyError: couldn't find key `doesnt exist`"}
  end
end
