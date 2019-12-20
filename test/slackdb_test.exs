defmodule SlackDBTest do
  use ExUnit.Case, async: false

  import Mox
  import SlackDB

  @searched_key %SlackDB.Key{
    channel_id: "cid",
    ts: "ts",
    key_phrase: "key_phrase",
    metadata: [:single_back],
    server_name: "server",
    channel_name: "cname"
  }

  @const_undeletable_searched_key %SlackDB.Key{
    channel_id: "cid",
    ts: "ts",
    key_phrase: "key_phrase",
    metadata: [:single_back, :constant, :undeletable],
    server_name: "server",
    channel_name: "cname"
  }

  @post_message_result %{
    "channel" => "CQGTEPMUL",
    "message" => %{
      "text" => "hello",
      "thread_ts" => "1573678209.000700",
      "ts" => "1576181323.002500",
      "type" => "message",
      "user" => "UQGHG5JF6"
    },
    "ok" => true,
    "ts" => "1576181323.002500"
  }

  @channel_info %{
    "id" => "C012AB3CD",
    "name" => "new"
  }

  # @auth_test_result %{
  #   "ok" => true,
  #   "user" => "slackdbot",
  #   "user_id" => "UQGHG5JF6",
  #   "bot_id" => "BQK7W4KKQ"
  # }

  setup :set_mox_global

  setup do
    SlackDB.Mock
    |> expect(:read, 2, fn
      "server", _, _ ->
        {:ok, "{\"new\":\"CQGTEPMUL\",\"new_private\":\"GQHDCMB9N\"}"}

      "un_initialized_server", _, _ ->
        {:error, "found_no_matches"}
    end)

    Search.Mock
    |> expect(:search, 4, fn
      _, _, "key_phrase", _ -> {:ok, @searched_key}
      _, _, "not_found", _ -> {:error, "found_no_matches"}
      _, _, "const_undeletable_key_phrase", _ -> {:ok, @const_undeletable_searched_key}
      _, _, "server", _ -> {:ok, @searched_key}
    end)

    Key.Mock
    |> expect(:get_value, 4, fn
      @searched_key -> {:ok, "key_value"}
    end)

    Messages.Mock
    |> expect(:wipe_thread, 1, fn
      @searched_key, _ -> {:ok, [{:ok, %{"ok" => true}}]}
    end)
    |> expect(:post_thread, 1, fn
      @searched_key, _ -> {:ok, [{:ok, @post_message_result}]}
    end)
    |> expect(:post_key_val, 2, fn
      _, _, _, _, _ -> {:ok, [ok: %{"ok" => true}]}
    end)

    Channels.Mock
    |> expect(:invite_to_channel, 1, fn
      _, _, _ -> {:ok, @channel_info}
    end)
    |> expect(:get_all_convos, 2, fn
      _ ->
        {:ok,
         [
           %{"id" => "CQ5H0K15Z", "name" => "general"},
           %{"id" => "CQ5H0JBDZ", "name" => "new"}
         ]}
    end)

    Client.Mock
    |> expect(:conversations_archive, 1, fn
      _, _ -> {:ok, %{"ok" => true}}
    end)
    |> expect(:conversations_create, 1, fn
      _, chnl, _ -> {:ok, @channel_info |> Map.put("name", chnl)}
    end)

    # |> expect(:auth_test, 5, fn _ -> {:ok, @auth_test_result} end)

    :ok
  end

  test "create" do
    {:ok, _pid} = SlackDB.Server.start_link()

    assert create("server", "new", "key_phrase", "value", :single_back) ==
             {:ok, [ok: %{"ok" => true}]}

    assert create("server", "new", "key_phrase :family:", "value", :single_back) ==
             {:error, "invalid_key_phrase"}
  end

  test "read" do
    assert read("server", "new", "key_phrase") == {:ok, "key_value"}
    assert read!("server", "new", "key_phrase") == "key_value"

    assert read("server", "new", "not_found") == {:error, "found_no_matches"}

    assert_raise RuntimeError, "found_no_matches", fn ->
      read!("server", "new", "not_found")
    end
  end

  test "update" do
    assert update("server", "new", "key_phrase", "value") ==
             {:ok, [ok: @post_message_result]}

    assert update("server", "new", "not_found", "value") ==
             {:error, "found_no_matches"}
  end

  test "delete" do
    assert delete("server", "new", "key_phrase") == {:ok, [ok: %{"ok" => true}]}
    assert delete("server", "new", "not_found") == {:error, "found_no_matches"}
  end

  test "append" do
    assert append("server", "new", "key_phrase", "value") ==
             {:ok, [ok: @post_message_result]}

    assert append("server", "new", "not_found", "value") ==
             {:error, "found_no_matches"}
  end

  test "invite_to_channel" do
    # {:ok, _pid} = SlackDB.Server.start_link()
  end

  test "invite_supervisors" do
    assert invite_supervisors("server", "user_id") ===
             {:ok, @channel_info}
  end

  test "new_channel" do
    {:ok, _pid} = SlackDB.Server.start_link()

    assert new_channel("server", "newly_created") ==
             {:ok,
              %{
                "un_initialized_server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{},
                  supervisor_channel_id: "CFC6MRQ07",
                  supervisor_channel_name: "slackdb-new-admins",
                  user_token: "xoxp"
                },
                "server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  supervisor_channel_id: "CFC6MRQ06",
                  supervisor_channel_name: "slackdb-admin",
                  user_token: "xoxp",
                  channels: %{
                    "new_private" => "GQHDCMB9N",
                    "new" => "CQGTEPMUL",
                    "newly_created" => "C012AB3CD"
                  }
                }
              }}
  end

  test "include_channel" do
    {:ok, _pid} = SlackDB.Server.start_link()

    assert include_channel("server", "general") ==
             {:ok,
              %{
                "un_initialized_server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{},
                  supervisor_channel_id: "CFC6MRQ07",
                  supervisor_channel_name: "slackdb-new-admins",
                  user_token: "xoxp"
                },
                "server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  supervisor_channel_id: "CFC6MRQ06",
                  supervisor_channel_name: "slackdb-admin",
                  user_token: "xoxp",
                  channels: %{
                    "new_private" => "GQHDCMB9N",
                    "new" => "CQGTEPMUL",
                    "general" => "CQ5H0K15Z"
                  }
                }
              }}

    assert include_channel("server", "not_found") == {:error, "channel_not_found"}
  end

  test "archive_channel" do
    {:ok, _pid} = SlackDB.Server.start_link()

    assert archive_channel("server", "new") ==
             {:ok,
              %{
                "server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{"new_private" => "GQHDCMB9N"},
                  supervisor_channel_id: "CFC6MRQ06",
                  supervisor_channel_name: "slackdb-admin",
                  user_token: "xoxp"
                },
                "un_initialized_server" => %{
                  bot_name: "Jeanie",
                  bot_token: "xoxb",
                  channels: %{},
                  supervisor_channel_id: "CFC6MRQ07",
                  supervisor_channel_name: "slackdb-new-admins",
                  user_token: "xoxp"
                }
              }}

    assert archive_channel("server", "blah") == {:error, "channel_name_not_in_database"}
  end

  test "dump" do
    {:ok, _pid} = SlackDB.Server.start_link()

    assert dump() == %{
             "server" => %{
               bot_name: "Jeanie",
               bot_token: "xoxb",
               channels: %{"new" => "CQGTEPMUL", "new_private" => "GQHDCMB9N"},
               supervisor_channel_id: "CFC6MRQ06",
               supervisor_channel_name: "slackdb-admin",
               user_token: "xoxp"
             },
             "un_initialized_server" => %{
               bot_name: "Jeanie",
               bot_token: "xoxb",
               channels: %{},
               supervisor_channel_id: "CFC6MRQ07",
               supervisor_channel_name: "slackdb-new-admins",
               user_token: "xoxp"
             }
           }
  end

  test "value screening" do
    {:ok, _pid} = SlackDB.Server.start_link()

    assert create("server", "new", "key_phrase", "value :family:", :single_back) ==
             {:error, "values_cannot_match_key_schema"}

    assert update("server", "new", "key_phrase", "value :family:") ==
             {:error, "values_cannot_match_key_schema"}

    assert append("server", "new", "key_phrase", "value :family:") ==
             {:error, "values_cannot_match_key_schema"}
  end
end
