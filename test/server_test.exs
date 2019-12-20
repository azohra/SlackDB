defmodule SlackDB.ServerTest do
  use ExUnit.Case

  import Mox
  import SlackDB.Server

  @channel_info %{
    "id" => "C012AB3CD",
    "name" => "general"
  }

  @auth_test_result %{
    "ok" => true,
    "user" => "slackdbot",
    "user_id" => "UQGHG5JF6",
    "bot_id" => "BQK7W4KKQ"
  }

  @server_state_json "{\"new\":\"CQGTEPMUL\",\"new_private\":\"GQHDCMB9N\"}"
  @server_state_map %{"new" => "CQGTEPMUL", "new_private" => "GQHDCMB9N"}

  setup do
    SlackDB.Mock
    |> expect(:read, 2, fn
      "server", _, _, _ ->
        {:ok, @server_state_json}

      "un_initialized_server", _, _, _ ->
        {:error, "found_no_matches"}
    end)

    Messages.Mock
    |> expect(:post_key_val, 1, fn
      _, _, _, _, _ -> {:ok, [ok: %{"ok" => true}]}
    end)

    Client.Mock
    |> expect(:conversations_archive, 2, fn
      _, "channel_works" -> {:ok, %{"ok" => true}}
      _, "channel_fails" -> {:error, "channel_failed"}
    end)
    |> expect(:auth_test, 1, fn _ -> {:ok, @auth_test_result} end)

    Channels.Mock
    |> expect(:invite_to_channel, 1, fn
      _, _, _ -> {:ok, @channel_info}
    end)

    :ok
  end

  test "init fails on config" do
    improper_config = %{
      "empty" => %{},
      "working" => %{
        bot_token: "xoxb",
        user_token: "xoxp",
        bot_name: "Jeanie",
        supervisor_channel_name: "slackdb-admin",
        supervisor_channel_id: "CFC6MRQ06"
      },
      "missing" => %{
        bot_token: "xoxb"
      }
    }

    assert init(improper_config) ==
             {:stop, "The following servers are improperly configured: empty, missing"}
  end

  test "init proper" do
    config = %{
      "server" => %{
        bot_token: "xoxb",
        user_token: "xoxp",
        bot_name: "Jeanie",
        supervisor_channel_name: "slackdb-admin",
        supervisor_channel_id: "CFC6MRQ06"
      }
    }

    assert init(config) ==
             {:ok,
              config
              |> put_in(["server", :bot_user_id], @auth_test_result["user_id"])
              |> put_in(["server", :channels], @server_state_map)}
  end

  test "init initialize server" do
    config = %{
      "un_initialized_server" => %{
        bot_token: "xoxb",
        user_token: "xoxp",
        bot_name: "Jeanie",
        supervisor_channel_name: "slackdb-admin",
        supervisor_channel_id: "CFC6MRQ06"
      }
    }

    assert init(config) ==
             {:ok,
              config
              |> put_in(["un_initialized_server", :bot_user_id], @auth_test_result["user_id"])
              |> put_in(["un_initialized_server", :channels], %{})}
  end

  test "handle_call put_channel" do
    state = %{"server" => %{channels: %{}}}
    new_state = %{"server" => %{channels: %{"new_channel" => "new_id"}}}

    assert handle_call({:put_channel, "server", "new_channel", "new_id"}, nil, state) ==
             {:reply, {:ok, new_state}, new_state}
  end

  test "handle_call archive" do
    state = %{
      "server" => %{
        user_token: "xoxp",
        channels: %{"channel_works" => "channel_works", "channel_fails" => "channel_fails"}
      }
    }

    assert handle_call({:archive, "server", "channel_works"}, nil, state) ==
             {:reply, {:ok, %{"ok" => true}},
              %{
                "server" => %{channels: %{"channel_fails" => "channel_fails"}, user_token: "xoxp"}
              }}

    assert handle_call({:archive, "server", "channel_fails"}, nil, state) ==
             {:reply, {:error, "channel_failed"}, state}

    assert handle_call({:archive, "server", "channel_doesnt_exist"}, nil, state) ==
             {:reply, {:error, "channel_name_not_in_database"}, state}
  end

  test "handle_call invite" do
    state = %{"server" => %{user_token: "xoxp", channels: %{"channel_works" => "channel_works"}}}

    assert handle_call({:invite, "server", "channel_works", ["id1", "id2"]}, nil, state) ==
             {:reply, {:ok, @channel_info}, state}
  end

  test "handle_call create" do
    state = %{"server" => %{user_token: "xoxp", channels: %{"channel_works" => "channel_works"}}}

    assert handle_call(
             {:create, "server", "channel_works", "key_phrase", "values", [:single_back]},
             nil,
             state
           ) == {:reply, {:ok, [ok: %{"ok" => true}]}, state}
  end

  test "handle_call dump" do
    state = %{"server" => %{user_token: "xoxp", channels: %{"channel_works" => "channel_works"}}}

    assert handle_call({:dump}, nil, state) == {:reply, state, state}
  end
end
