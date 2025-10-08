#!/usr/bin/env elixir

# Real Integration Test for Google Routes API Distance Matrix
# This script makes actual API calls to Google's Routes API
#
# Usage:
#   1. Set your API key: export GOOGLE_MAPS_API_KEY="your_actual_api_key"
#   2. Run: elixir integration_test.exs

Mix.install([
  {:google_maps, path: "."},
  {:jason, "~> 1.1"},
  {:httpoison, "~> 1.7"}
])

defmodule IntegrationTest do
  alias GoogleMaps.Request
  alias GoogleMaps.Response

  def run do
    # Check if API key is available
    api_key = System.get_env("GOOGLE_MAPS_API_KEY") ||
              Application.get_env(:google_maps, :api_key)

    unless api_key do
      IO.puts """
      ❌ Error: No API key found!

      Please set your Google Maps API key in one of these ways:
      1. Environment variable: export GOOGLE_MAPS_API_KEY="your_key_here"
      2. Application config: Application.put_env(:google_maps, :api_key, "your_key_here")

      You can get an API key from: https://console.cloud.google.com/
      Make sure to enable the Routes API for your project.
      """
      System.halt(1)
    end

    IO.puts "🚀 Starting Google Routes API Integration Test"
    IO.puts "📍 Using API key: #{String.slice(api_key, 0, 8)}..."
    IO.puts ""

    # Configure the app to use HTTPoison for real requests
    Application.put_env(:google_maps, :requester, HTTPoison)
    Application.put_env(:google_maps, :api_key, api_key)

    # Configure HTTPoison to ignore SSL verification for corporate proxies
    HTTPoison.start()

    IO.puts "🔧 Configuring HTTPoison for corporate proxy environment..."
    IO.puts "   - Disabling SSL verification"
    IO.puts "   - Setting relaxed SSL options"
    IO.puts ""

    # Test 1: Simple coordinate to coordinate
    test_coordinate_to_coordinate()

    # Test 2: Address to coordinates
    test_address_to_coordinates()

    # Test 3: Multiple origins and destinations
    test_multiple_waypoints()

    # Test 4: Place ID usage
    test_place_id()

    IO.puts "✅ Integration test completed!"
  end

  defp test_coordinate_to_coordinate do
    IO.puts "🧪 Test 1: Coordinate to Coordinate"
    IO.puts "   From: Greenville, SC (34.8526, -82.3940)"
    IO.puts "   To: Charlotte, NC (35.2271, -80.8431)"

    params = [
      origins: [{34.8526, -82.3940}],
      destinations: [{35.2271, -80.8431}],
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE",
      options: ssl_options()
    ]

    case Request.post("distance_matrix", params) do
      {:ok, response} ->
        print_response("Coordinate to Coordinate", response)
      {:error, error} ->
        IO.puts "   ❌ Error: #{inspect(error)}"
    end

    IO.puts ""
  end

  defp test_address_to_coordinates do
    IO.puts "🧪 Test 2: Address to Coordinates"
    IO.puts "   From: 100 Main St, Greenville, SC"
    IO.puts "   To: Charlotte, NC (35.2271, -80.8431)"

    params = [
      origins: ["100 Main St, Greenville, SC"],
      destinations: [{35.2271, -80.8431}],
      travelMode: "DRIVE",
      options: ssl_options()
    ]

    case Request.post("distance_matrix", params) do
      {:ok, response} ->
        print_response("Address to Coordinates", response)
      {:error, error} ->
        IO.puts "   ❌ Error: #{inspect(error)}"
    end

    IO.puts ""
  end

  defp test_multiple_waypoints do
    IO.puts "🧪 Test 3: Multiple Origins and Destinations"
    IO.puts "   Origins: Greenville SC, Spartanburg SC"
    IO.puts "   Destinations: Charlotte NC, Atlanta GA"

    params = [
      origins: [
        {34.8526, -82.3940},  # Greenville, SC
        {34.9496, -81.9322}   # Spartanburg, SC
      ],
      destinations: [
        {35.2271, -80.8431},  # Charlotte, NC
        {33.7490, -84.3880}   # Atlanta, GA
      ],
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE",
      options: ssl_options()
    ]

    case Request.post("distance_matrix", params) do
      {:ok, response} ->
        print_response("Multiple Waypoints", response)
      {:error, error} ->
        IO.puts "   ❌ Error: #{inspect(error)}"
    end

    IO.puts ""
  end

  defp test_place_id do
    IO.puts "🧪 Test 4: Using Place ID"
    IO.puts "   From: Coordinates (34.8526, -82.3940)"
    IO.puts "   To: Place ID (example - may not be valid)"

    params = [
      origins: [{34.8526, -82.3940}],
      destinations: [{:place_id, "ChIJ7cv00DwHZogR_kE9iGSUZuI"}], # Example Place ID
      travelMode: "DRIVE",
      options: ssl_options()
    ]

    case Request.post("distance_matrix", params) do
      {:ok, response} ->
        print_response("Place ID", response)
      {:error, error} ->
        IO.puts "   ❌ Error: #{inspect(error)}"
        IO.puts "   (This might fail if the Place ID is invalid)"
    end

    IO.puts ""
  end

  # SSL options to bypass certificate verification for corporate proxies
  defp ssl_options do
    [
      ssl: [
        verify: :verify_none,
        verify_fun: {fn _, _, _ -> {:valid, []} end, []},
        check_hostname: false,
        versions: [:"tlsv1.2", :"tlsv1.3"]
      ],
      recv_timeout: 30_000,
      timeout: 30_000
    ]
  end

  defp print_response(test_name, response) do
    IO.puts "   ✅ #{test_name} - Success!"

    # Try to extract useful information from the response
    case response do
      %{"status" => status} when status != "OK" ->
        IO.puts "   ⚠️  API Status: #{status}"
        if error_message = response["error_message"] do
          IO.puts "   📝 Error: #{error_message}"
        end

      %{"originIndex" => origin_index, "destinationIndex" => dest_index} = result ->
        IO.puts "   📊 Route from origin #{origin_index} to destination #{dest_index}:"

        if duration = get_in(result, ["duration"]) do
          IO.puts "   ⏱️  Duration: #{duration}"
        end

        if distance = get_in(result, ["distanceMeters"]) do
          distance_km = distance / 1000
          IO.puts "   📏 Distance: #{Float.round(distance_km, 2)} km"
        end

        if status = get_in(result, ["status"]) do
          IO.puts "   🚦 Status: #{status}"
        end

      response ->
        IO.puts "   📄 Raw response keys: #{inspect(Map.keys(response))}"

        # Print first few lines of response for debugging
        response_str = inspect(response, limit: :infinity, pretty: true)
        lines = String.split(response_str, "\n")
        preview = lines |> Enum.take(5) |> Enum.join("\n")
        IO.puts "   📋 Response preview:"
        IO.puts "   #{preview}"
        if length(lines) > 5 do
          IO.puts "   ... (truncated)"
        end
    end
  end
end

# Run the integration test
IntegrationTest.run()
