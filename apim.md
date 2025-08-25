Yes, Duration of Backend Requests is one of the key metrics for checking latency in Azure API Management (APIM), but let me explain what it shows and what else you should consider:
What "Duration of Backend Requests" Shows
This metric specifically measures:

The time APIM spends waiting for the backend service to respond
The duration from when APIM sends the request to your backend API until it receives the response
This is essentially the backend latency portion of the total request

For Complete Latency Analysis, Also Check:

Overall Gateway Requests (Duration)

Shows the total end-to-end latency
Includes all processing time from when APIM receives the request until it sends the response back to the client


Service Time

The time spent processing within APIM itself
Calculated as: Overall Duration - Backend Duration - Client Duration


Capacity metric

High capacity utilization (>60-80%) can contribute to latency issues
Shows the CPU utilization of the APIM gateway



How to Analyze in Azure Portal
Navigate to:
Your APIM Instance → Monitoring → Metrics
Then select:

Metric: Duration of Backend Requests (or the others mentioned)
Aggregation: Avg, P95, P99, or Max (P95/P99 are particularly useful for latency analysis)
Time range: Adjust based on when you're seeing issues
