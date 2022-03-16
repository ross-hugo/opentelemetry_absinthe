defmodule OpentelemetryAbsinthe.BatchInstrumentation do
  @moduledoc """
  Module for automatic instrumentation of Absinthe batch resolution.

  It works by listening to [:absinthe, :middleware, :batch, :start/:stop] telemetry events,
  which are emitted by Absinthe only since v1.5; therefore it won't work on previous versions.

  (you can still call `OpentelemetryAbsinthe.BatchInstrumentation.setup()` in your application startup
  code, it just won't do anything.)
  """

  require Record

  @tracer_id __MODULE__

  @default_config [
    batch_span_name: "absinthe graphql batch"
  ]

  def setup(instrumentation_opts \\ []) do
    config =
      @default_config
      |> Keyword.merge(Application.get_env(:opentelemetry_absinthe, :trace_options, []))
      |> Keyword.merge(instrumentation_opts)
      |> Enum.into(%{})

    :telemetry.attach(
      {__MODULE__, :batch_start},
      [:absinthe, :middleware, :batch, :start],
      &__MODULE__.handle_batch_start/4,
      config
    )

    :telemetry.attach(
      {__MODULE__, :batch_stop},
      [:absinthe, :middleware, :batch, :stop],
      &__MODULE__.handle_batch_stop/4,
      config
    )
  end

  def teardown do
    :telemetry.detach({__MODULE__, :batch_start})
    :telemetry.detach({__MODULE__, :batch_stop})
  end

  def handle_batch_start(_event_name, _measurements, metadata, config) do
    batch_function_name = get_batch_function_as_string(metadata.batch_fun)
    attributes = [{"graphql.batch.function", batch_function_name}]

    execution_ctx =
      OpentelemetryAbsinthe.Registry.get_absinthe_execution_span() || OpenTelemetry.Tracer.current_span_ctx()

    OpenTelemetry.Tracer.set_current_span(execution_ctx)

    OpentelemetryTelemetry.start_telemetry_span(
      @tracer_id,
      "#{config.batch_span_name} #{batch_function_name}",
      metadata,
      %{
        kind: :server,
        attributes: attributes
      }
    )
  end

  def handle_batch_stop(_event_name, _measurements, data, _config) do
    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, data)
  end

  # Get batch function as string, the value should come from metadata.batch_fun at telemetry event function
  # correspond to data format at https://hexdocs.pm/absinthe/Absinthe.Middleware.Batch.html#t:batch_fun/0
  defp get_batch_function_as_string(batch_fun)
  defp get_batch_function_as_string({module, func}), do: "#{module} #{func}"
  defp get_batch_function_as_string({module, func, first_arg}), do: "#{module} #{func} #{inspect(first_arg)}"
end