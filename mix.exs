defmodule SlackDB.MixProject do
  use Mix.Project

  def project do
    [
      app: :slackdb,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      description: description(),
      deps: deps(),
      package: package(),
      aliases: aliases(),
      name: "slackdb",
      source_url: "https://github.com/azohra/slackdb",
      docs: [
        main: "README.md",
        extras: [
          "README.md": [filename: "README.md", title: "SlackDB"]
        ]
      ]
    ]
  end

  def application do
    []
  end

  defp aliases do
    [docs: ["docs", &copy_images/1]]
  end

  defp copy_images(_) do
    File.cp_r("design", "doc/design", fn source, destination ->
      IO.gets("Overwriting #{destination} by #{source}. Type y to confirm. ") == "y\n"
    end)

    # File.cp_r("doc", "docs", fn _source, _destination ->
    #   true
    # end)
  end

  defp deps do
    [
      {:tesla, "~> 1.2.1"},
      {:jason, ">= 1.0.0"},
      {:private, "~> 0.1.1"},
      {:flow, "~> 0.14"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description() do
    "A key/value database courtesy of Slack 🙃"
  end

  defp package() do
    [
      name: "slackdb",
      licenses: ["MIT"],
      maintainers: ["Borna Houmani-Farahani", "Brandon Sam Soon", "Frank Vumbaca", "Kevin Hu"],
      links: %{"GitHub" => "https://github.com/azohra/slackdb"}
    ]
  end
end
