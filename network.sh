#!/bin/bash

# Bitwarden Network Diagnostics Script
# Usage: ./bitwarden-test.sh [domain] [namespace] [use-self-signed]

DOMAIN=${1:-"bitwarden-test.abcorp.com"}
NAMESPACE=${2:-"default"}
USE_SELF_SIGNED=${3:-"false"}
LOG_FILE="bitwarden-diagnostics-$(date +%Y%m%d-%H%M%S).log"

# Set curl options based on certificate type
if [[ "$USE_SELF_SIGNED" == "true" ]]; then
    CURL_OPTS="-k"
    echo "Using self-signed certificate mode (-k flag)"
else
    CURL_OPTS=""
    echo "Using standard SSL verification"
fi

echo "=== Bitwarden Network Diagnostics ===" | tee $LOG_FILE
echo "Domain: $DOMAIN" | tee -a $LOG_FILE
echo "Namespace: $NAMESPACE" | tee -a $LOG_FILE
echo "Started: $(date)" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# 1. Basic connectivity test
echo "=== 1. Basic Connectivity Test ===" | tee -a $LOG_FILE
for i in {1..10}; do
    echo -n "Test $i: " | tee -a $LOG_FILE
    if curl $CURL_OPTS -s -o /dev/null -w "%{http_code} - %{time_total}s" --max-time 10 https://$DOMAIN/; then
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
    response=$(curl $CURL_OPTS -s -o /dev/null -w "%{http_code},%{time_total},%{time_namelookup},%{time_connect}" --max-time 15 https://$DOMAIN/ 2>&1)
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
        response=$(curl $CURL_OPTS -s -o /dev/null -w "%{http_code} %{time_total}s" --max-time 10 https://$DOMAIN$endpoint 2>&1)
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
        response=$(curl $CURL_OPTS -s -o /dev/null -w "Thread$i: %{http_code} %{time_total}s" --max-time 10 https://$DOMAIN/)
        echo "$response" >> $LOG_FILE
    ) &
done
wait
echo "Concurrent test completed" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# 5. SSL Certificate Test
echo "=== 5. SSL Certificate Test ===" | tee -a $LOG_FILE
echo "Testing SSL verification vs bypass:" | tee -a $LOG_FILE

# Test with SSL verification
echo "With SSL verification:" | tee -a $LOG_FILE
for i in {1..3}; do
    response=$(curl -s -o /dev/null -w "  %{http_code} %{time_total}s" --max-time 10 https://$DOMAIN/ 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "  Test $i: $response ✓" | tee -a $LOG_FILE
    else
        echo "  Test $i: SSL_ERROR ✗" | tee -a $LOG_FILE
    fi
done

# Test bypassing SSL verification
echo "Bypassing SSL verification (-k):" | tee -a $LOG_FILE
for i in {1..3}; do
    response=$(curl -k -s -o /dev/null -w "  %{http_code} %{time_total}s" --max-time 10 https://$DOMAIN/ 2>&1)
    echo "  Test $i: $response" | tee -a $LOG_FILE
done
echo "" | tee -a $LOG_FILE

# 6. DNS resolution test
echo "=== 6. DNS Resolution Test ===" | tee -a $LOG_FILE
for i in {1..5}; do
    echo "DNS lookup $i:" | tee -a $LOG_FILE
    dig +short $DOMAIN | tee -a $LOG_FILE
    nslookup $DOMAIN | grep -A2 "Name:" | tee -a $LOG_FILE
    echo "" | tee -a $LOG_FILE
    sleep 1
done

echo "=== Diagnostics completed at $(date) ===" | tee -a $LOG_FILE
echo "Results saved to: $LOG_FILE" | tee -a $LOG_FILE

# Additional SSL debugging info
if [[ "$USE_SELF_SIGNED" == "true" ]]; then
    echo "" | tee -a $LOG_FILE
    echo "=== SSL Certificate Information ===" | tee -a $LOG_FILE
    echo "Certificate details:" | tee -a $LOG_FILE
    openssl s_client -connect $DOMAIN:443 -servername $DOMAIN < /dev/null 2>/dev/null | openssl x509 -text -noout | grep -A5 "Subject:\|Issuer:\|Not After" | tee -a $LOG_FILE
    echo "" | tee -a $LOG_FILE
    echo "Certificate expiry check:" | tee -a $LOG_FILE
    echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -dates | tee -a $LOG_FILE
fi
