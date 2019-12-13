defmodule SlackDB.Client do
  @moduledoc false

  use Tesla

  require Logger

  @callback search_messages(String.t(), String.t(), keyword()) ::
              {:error, any()} | {:ok, map()}
  @callback chat_postMessage(String.t(), String.t(), String.t(), keyword()) ::
              {:error, any()} | {:ok, map()}
  @callback chat_delete(String.t(), String.t(), String.t()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_create(String.t(), String.t(), keyword()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_archive(String.t(), String.t()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_invite(String.t(), String.t(), String.t()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_list(String.t(), keyword()) ::
              {:error, any()} | {:ok, map()}
  @callback conversations_replies(String.t(), SlackDB.Key.t(), keyword()) ::
              {:error, any()} | {:ok, map()}

  @base_url "https://slack.com/api"

  @doc """
  ## Options
  * `:page` - integer for pagination
  """
  @spec search_messages(String.t(), String.t(), keyword()) :: {:error, any()} | {:ok, map()}
  def search_messages(user_token, query, opts \\ []) do
    with {:ok, resp} <-
           client(user_token)
           |> post("/search.messages", %{
             query: query,
             highlight: false,
             sort: "timestamp",
             sort_dir: "desc",
             page: Keyword.get(opts, :page, 1)
             # count: 1
           }) do
      case resp.body |> Jason.decode!() |> IO.inspect() do
        %{"ok" => true, "messages" => messages} -> {:ok, messages}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @doc """
  ## Options
  * `:thread_ts` - slack timestamp string
  """
  @spec chat_postMessage(String.t(), String.t(), String.t(), keyword()) ::
          {:error, any()} | {:ok, map()}
  def chat_postMessage(bot_token, text, channel_id, opts \\ []) do
    with {:ok, resp} <-
           client(bot_token)
           |> post(
             "/chat.postMessage",
             %{
               channel: channel_id,
               text: text,
               as_user: true,
               thread_ts: Keyword.get(opts, :thread_ts, nil)
             }
           ) do
      case resp.body |> Jason.decode!() |> IO.inspect() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec chat_delete(String.t(), String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  def chat_delete(user_token, channel_id, ts) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/chat.delete",
             %{
               channel: channel_id,
               ts: ts
             }
           ) do
      case resp.body |> Jason.decode!() |> IO.inspect() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @doc """
  ## Options
  * `:is_private?` - boolean
  """
  @spec conversations_create(String.t(), String.t(), keyword()) :: {:error, any()} | {:ok, map()}
  def conversations_create(user_token, name, opts \\ []) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/conversations.create",
             %{
               name: name,
               validate: true,
               is_private: Keyword.get(opts, :is_private?, false)
             }
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true, "channel" => channel_info} -> {:ok, channel_info}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec conversations_archive(String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  def conversations_archive(user_token, id) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/conversations.archive",
             %{channel: id}
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => "already_archived"} -> {:ok, "already_archived"}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @spec conversations_invite(String.t(), String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  def conversations_invite(user_token, channel_id, comma_seperated_user_ids)
      when is_binary(comma_seperated_user_ids) do
    with {:ok, resp} <-
           client(user_token)
           |> post(
             "/conversations.invite",
             %{channel: channel_id, users: comma_seperated_user_ids}
           ) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true, "channel" => channel_info} -> {:ok, channel_info}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @doc """
  ## Options
  * `:limit` - integer <= 200, defaults to 200. represents number of conversations returned at once
  * `:cursor` - string for pagination, nil by default
  """
  @spec conversations_list(String.t(), keyword()) ::
          {:error, any()} | {:ok, map()}
  def conversations_list(user_token, opts \\ []) do
    with {:ok, resp} <-
           client(user_token)
           |> post("/conversations.list", %{
             exclude_archived: true,
             limit: Keyword.get(opts, :limit, 200),
             cursor: Keyword.get(opts, :cursor, nil),
             types: "public_channel,private_channel"
           }) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  @doc """
  ## Options
  * `:limit` - integer <= 200, defaults to 200. represents number of conversations returned at once
  * `:cursor` - string for pagination, nil by default
  """
  @spec conversations_replies(String.t(), SlackDB.Key.t(), keyword()) ::
          {:error, any()} | {:ok, map()}
  def conversations_replies(user_token, key, opts \\ []) do
    with {:ok, resp} <-
           client(user_token)
           |> post("/conversations.replies", %{
             channel: key.channel_id,
             ts: key.ts,
             limit: Keyword.get(opts, :limit, 200),
             cursor: Keyword.get(opts, :cursor, nil)
           }) do
      case resp.body |> Jason.decode!() do
        %{"ok" => true} = body -> {:ok, body}
        %{"ok" => false, "error" => error} -> {:error, error}
        _ -> {:error, resp.status}
      end
    end
  end

  defp client(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, @base_url},
      {Tesla.Middleware.Headers,
       [
         {"authorization", "Bearer " <> token}
       ]},
      {Tesla.Middleware.FormUrlencoded, []}
    ]

    Tesla.client(middleware)
  end

  # defp parse_slack_response(resp, pull_key) do
  #   case resp.body |> Jason.decode!() do
  #     %{"ok" => true} = body -> {:ok, body}
  #     %{"ok" => false, "error" => error} -> {:error, error}
  #     _ -> {:error, resp.status}
  #   end
  # end

  # def get_message(token, channel, ts) do
  #   with {:ok, resp} <-
  #          client(token)
  #          |> post("/channels.history", %{
  #            channel: channel,
  #            latest: ts,
  #            inclusive: true,
  #            count: 1
  #          }) do
  #     case resp.body |> Jason.decode!() do
  #       %{"ok" => true, "messages" => [message]} -> {:ok, message}
  #       %{"ok" => false, "error" => error} -> {:error, error}
  #       _ -> {:error, resp.status}
  #     end
  #   end
  # end

  # @spec reactions_get(String.t(), String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  # def reactions_get(bot_token, channel_id, ts) do
  #   with {:ok, resp} <-
  #          client(bot_token)
  #          |> post(
  #            "/reactions.get",
  #            %{
  #              channel: channel_id,
  #              timestamp: ts,
  #              full: true
  #            }
  #          ) do
  #     case resp.body |> Jason.decode!() do
  #       %{"ok" => true} = body -> {:ok, body}
  #       %{"ok" => false, "error" => error} -> {:error, error}
  #       _ -> {:error, resp.status}
  #     end
  #   end
  # end

  # @spec conversations_join(String.t(), String.t()) :: {:error, any()} | {:ok, map()}
  # def conversations_join(user_token, channel_id) do
  #   with {:ok, resp} <-
  #          client(user_token)
  #          |> post(
  #            "/conversations.join",
  #            %{channel: channel_id}
  #          ) do
  #     case resp.body |> Jason.decode!() do
  #       %{"ok" => true, "channel" => channel_info} -> {:ok, channel_info}
  #       %{"ok" => false, "error" => error} -> {:error, error}
  #       _ -> {:error, resp.status}
  #     end
  #   end
  # end
end
