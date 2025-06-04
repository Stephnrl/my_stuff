#!/bin/bash

# Bitwarden Network Diagnostics Script
# Usage: ./bitwarden-test.sh [domain] [namespace]

DOMAIN=${1:-"bitwarden-test.abcorp.com"}
NAMESPACE=${2:-"default"}
LOG_FILE="bitwarden-diagnostics-$(date +%Y%m%d-%H%M%S).log"

echo "=== Bitwarden Network Diagnostics ===" | tee $LOG_FILE
echo "Domain: $DOMAIN" | tee -a $LOG_FILE
echo "Namespace: $NAMESPACE" | tee -a $LOG_FILE
echo "Started: $(date)" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# 1. Basic connectivity test
echo "=== 1. Basic Connectivity Test ===" | tee -a $LOG_FILE
for i in {1..10}; do
    echo -n "Test $i: " | tee -a $LOG_FILE
    if curl -s -o /dev/null -w "%{http_code} - %{time_total}s" --max-time 10 https://$DOMAIN/; then
        echo " ✓" | tee -a $LOG_FILE
    else
        echo " ✗ TIMEOUT" | tee -a $LOG_FILE
    fi
    sleep 2
done
echo "" | tee -a $LOG_FILE

# 2. Response time monitoring
echo "=== 2. Response Time Monitoring (30 tests) ===" | tee -a $LOG_FILE
echo "Time,Status,Response_Time,Total_Time,DNS_Time,Connect_Time" | tee -a $LOG_FILE
for i in {1..30}; do
    timestamp=$(date '+%H:%M:%S')
    response=$(curl -s -o /dev/null -w "%{http_code},%{time_total},%{time_namelookup},%{time_connect}" --max-time 15 https://$DOMAIN/ 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "$timestamp,$response" | tee -a $LOG_FILE
    else
        echo "$timestamp,TIMEOUT,15.0,15.0,15.0" | tee -a $LOG_FILE
    fi
    sleep 3
done
echo "" | tee -a $LOG_FILE

# 3. Different endpoint tests
echo "=== 3. Different Endpoint Tests ===" | tee -a $LOG_FILE
endpoints=("/api/alive" "/api/version" "/admin" "/identity" "/api/accounts/profile")
for endpoint in "${endpoints[@]}"; do
    echo "Testing $endpoint:" | tee -a $LOG_FILE
    for i in {1..5}; do
        response=$(curl -s -o /dev/null -w "%{http_code} %{time_total}s" --max-time 10 https://$DOMAIN$endpoint 2>&1)
        echo "  Attempt $i: $response" | tee -a $LOG_FILE
        sleep 1
    done
    echo "" | tee -a $LOG_FILE
done

# 4. Concurrent connection test
echo "=== 4. Concurrent Connection Test ===" | tee -a $LOG_FILE
echo "Running 5 concurrent requests..." | tee -a $LOG_FILE
for i in {1..5}; do
    (
        response=$(curl -s -o /dev/null -w "Thread$i: %{http_code} %{time_total}s" --max-time 10 https://$DOMAIN/)
        echo "$response" >> $LOG_FILE
    ) &
done
wait
echo "Concurrent test completed" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# 5. DNS resolution test
echo "=== 5. DNS Resolution Test ===" | tee -a $LOG_FILE
for i in {1..5}; do
    echo "DNS lookup $i:" | tee -a $LOG_FILE
    dig +short $DOMAIN | tee -a $LOG_FILE
    nslookup $DOMAIN | grep -A2 "Name:" | tee -a $LOG_FILE
    echo "" | tee -a $LOG_FILE
    sleep 1
done

echo "=== Diagnostics completed at $(date) ===" | tee -a $LOG_FILE
echo "Results saved to: $LOG_FILE" | tee -a $LOG_FILE
