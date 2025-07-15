# Get access token
sa_token=$(curl --silent \
  --url 'https://login.dso.mil/auth/realms/baby-yoda/protocol/openid-connect/token' \
  --header 'content-type: application/x-www-form-urlencoded' \
  --data grant_type=client_credentials \
  --data client_id="$client_id" \
  --data client_secret="$client_secret" | jq .access_token -r)

# Query VAT API
curl --oauth2-bearer "$sa_token" "https://vat.dso.mil/api/p1/containers?state=All"
