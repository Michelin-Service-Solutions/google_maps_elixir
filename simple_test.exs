#!/usr/bin/env elixir

# Simple API connectivity test
# Usage: GOOGLE_MAPS_API_KEY="your_key" elixir simple_test.exs

Mix.install([
  {:google_maps, path: "."},
  {:jason, "~> 1.1"},
  {:httpoison, "~> 1.7"}
])

# Configure for real API calls
Application.put_env(:google_maps, :requester, HTTPoison)

# Start HTTPoison
HTTPoison.start()

# SSL options for corporate proxy environments
ssl_options = [
  ssl: [
    verify: :verify_none,
    verify_fun: {fn _, _, _ -> {:valid, []} end, []},
    check_hostname: false,
    versions: [:"tlsv1.2", :"tlsv1.3"]
  ],
  recv_timeout: 30_000,
  timeout: 30_000
]

# Simple test from Greenville, SC to Charlotte, NC
params = [
  origins: [{34.8526, -82.3940}],  # Greenville, SC
  destinations: [{35.2271, -80.8431}], # Charlotte, NC
  travelMode: "DRIVE",
  routingPreference: "TRAFFIC_AWARE",
  options: ssl_options
]

IO.puts "Making API call to Google Routes API..."
IO.puts "From: Greenville, SC to Charlotte, NC"

case GoogleMaps.Request.post("distance_matrix", params) do
  {:ok, response} ->
    IO.puts "\n✅ Success!"
    IO.puts "Response: #{inspect(response, pretty: true)}"

  {:error, error} ->
    IO.puts "\n❌ Error occurred:"
    IO.puts "#{inspect(error, pretty: true)}"

  {:error, status, message} ->
    IO.puts "\n❌ API Error:"
    IO.puts "Status: #{status}"
    IO.puts "Message: #{message}"
end
