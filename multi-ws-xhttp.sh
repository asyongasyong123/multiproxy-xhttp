#!/bin/bash
set -euo pipefail

# =========================================
# 🚀 GCP-XRAY MULTI-ENGINE DEPLOYER
# ✅ ENGINES: OPENRESTY, ENVOY, HAPROXY
# ✅ PROTOCOLS: WS & XHTTP
# ✅ INTEGRATED DNS & ADBLOCK ROUTING
# ✅ FLEXIBLE REGIONS & RESOURCE ALLOCATION
# =========================================

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

# ==============================================
# AUTO INSTALL JQ IF MISSING
# ==============================================
if ! command -v jq &> /dev/null; then
  echo -e "\n${YELLOW}⚠️ Installing required tool: jq...${NC}"
  sudo apt update -qq && sudo apt install -y -qq jq || {
    echo -e "${RED}❌ Failed to install jq!${NC}"
    exit 1
  }
  echo -e "${GREEN}✅ jq installed successfully!${NC}"
fi

# ==============================================
# LIST SERVICES
# ==============================================
list_deployed_services() {
  echo -e "\n======================================"
  echo -e "${CYAN}📋 ALL DEPLOYED GCP-XRAY SERVICES - FULL DETAILS${NC}"
  echo -e "======================================"
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
  echo "Project: $PROJECT_ID"
  echo ""

  declare -A REGION_NAMES=(
    ["us-central1"]="Iowa, United States 🇺🇸"
    ["us-east1"]="South Carolina, United States 🇺🇸"
    ["us-east4"]="N. Virginia, United States 🇺🇸"
    ["us-west1"]="Oregon, United States 🇺🇸"
    ["asia-east1"]="Taiwan 🇹🇼"
    ["asia-southeast1"]="Singapore 🇸🇬"
    ["asia-northeast1"]="Tokyo, Japan 🇯🇵"
    ["asia-northeast3"]="Seoul, South Korea 🇰🇷"
    ["europe-west1"]="Belgium 🇧🇪"
    ["europe-west4"]="Netherlands 🇳🇱"
    ["europe-west9"]="Paris, France 🇫🇷"
    ["asia-south1"]="Mumbai, India 🇮🇳"
  )

  SERVICES=$(gcloud run services list \
    --format="value(metadata.name, status.url, region, metadata.creationTimestamp.date(%Y-%m-%d))" \
    --project="$PROJECT_ID" 2>/dev/null)

  if [ -z "$SERVICES" ]; then
    echo -e "${RED}❌ No services found.${NC}"
  else
    local COUNT=1
    while IFS=$'\t' read -r NAME URL REGION CREATED; do
      [ -z "$NAME" ] && continue
      FULL_REGION="${REGION_NAMES[$REGION]:-$REGION}"

      DETAILS=$(gcloud run services describe "$NAME" --region "$REGION" --project="$PROJECT_ID" --format=json 2>/dev/null)

      MEMORY=$(echo "$DETAILS" | jq -r '.spec.template.spec.containers[0].resources.limits.memory // "1Gi"')
      CPU=$(echo "$DETAILS" | jq -r '.spec.template.spec.containers[0].resources.limits.cpu // "1"')
      BILLING=$(echo "$DETAILS" | jq -r '.spec.template.spec.billingMode // "Instance Based"' | sed 's/_/ /g;s/^./\U&/')
      MIN_INST=$(echo "$DETAILS" | jq -r '.spec.template.spec.minInstances // "0"')
      MAX_INST=$(echo "$DETAILS" | jq -r '.spec.template.spec.maxInstances // "1"')
      CONCURRENCY=$(echo "$DETAILS" | jq -r '.spec.template.spec.containerConcurrency // "300"')
      TIMEOUT=$(echo "$DETAILS" | jq -r '.spec.template.spec.timeoutSeconds // "300"')

      echo -e "${GREEN}=== SERVICE #$COUNT ===${NC}"
      echo "🔹 Name:         $NAME"
      echo "🔹 URL:          $URL"
      echo "🔹 Region:       $REGION → $FULL_REGION"
      echo "🔹 Created:      $CREATED"
      echo "🔹 Resources:    $MEMORY RAM | $CPU vCPU"
      echo "🔹 Billing:      $BILLING"
      echo "🔹 Instances:    Min $MIN_INST / Max $MAX_INST"
      echo "🔹 Connections:  Max $CONCURRENCY"
      echo "🔹 Timeout:      ${TIMEOUT}s"
      echo ""
      ((COUNT++))
    done <<< "$SERVICES"
  fi
  
  echo -e "\n======================================"
  read -p "Press [Enter] to return..."
}

# ==============================================
# REGION SELECTOR
# ==============================================
select_region() {
  echo -e "\n=== GCP CLOUD RUN REGION SELECTION ==="
  echo "--- North America ---"
  echo "1) us-central1      (Iowa, US 🇺🇸)"
  echo "2) us-east1         (South Carolina, US 🇺🇸)"
  echo "3) us-east4         (N. Virginia, US 🇺🇸)"
  echo "4) us-west1         (Oregon, US 🇺🇸)"
  echo ""
  echo "--- Asia Pacific ---"
  echo "5) asia-east1       (Taiwan 🇹🇼 — RECOMMENDED!)"
  echo "6) asia-southeast1  (Singapore 🇸🇬)"
  echo "7) asia-northeast1   (Tokyo, Japan 🇯🇵)"
  echo "8) asia-northeast3   (Seoul, South Korea 🇰🇷)"
  echo "9) asia-south1      (Mumbai, India 🇮🇳)"
  echo ""
  echo "--- Europe ---"
  echo "10) europe-west1     (Belgium 🇧🇪)"
  echo "11) europe-west4    (Netherlands 🇳🇱)"
  echo "12) europe-west9    (Paris, France 🇫🇷)"
  echo ""
  echo "0) Enter custom region code"
  echo ""

  read -p "Enter region number: " REGION_NUM

  case $REGION_NUM in
    1) REGION="us-central1" ;;
    2) REGION="us-east1" ;;
    3) REGION="us-east4" ;;
    4) REGION="us-west1" ;;
    5) REGION="asia-east1" ;;
    6) REGION="asia-southeast1" ;;
    7) REGION="asia-northeast1" ;;
    8) REGION="asia-northeast3" ;;
    9) REGION="asia-south1" ;;
    10) REGION="europe-west1" ;;
    11) REGION="europe-west4" ;;
    12) REGION="europe-west9" ;;
    0) read -p "Type full region code: " REGION ;;
    *) echo -e "${YELLOW}⚠️ Invalid! Using us-central1${NC}"; REGION="us-central1" ;;
  esac

  echo -e "${GREEN}✅ Selected Region:${NC} $REGION"
}

# ==============================================
# DEPLOYMENT FUNCTION
# ==============================================
deploy_new_service() {
  select_region

  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
  if [ -z "$PROJECT_ID" ]; then
      echo -e "${RED}❌ No project set! Run: gcloud config set project YOUR_ID${NC}"
      read -p "Press [Enter] to return..."
      return
  fi

  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --project="$PROJECT_ID" --quiet

  # ==============================================
  # 🎯 PROXY ENGINE SELECTOR
  # ==============================================
  echo -e "\n${CYAN}=========================================${NC}"
  echo -e "${GREEN}          CHOOSE PROXY ENGINE${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo "1) OpenResty          - [Standard / Highly Reliable] ✅"
  echo "2) Envoy Proxy        - [High Performance / Cloud Native]"
  echo "3) HAProxy            - [Ultra Low Latency / Lightweight]"
  while true; do
      read -p "Select Engine [1-3]: " ENGINE_CHOICE
      case $ENGINE_CHOICE in
          1) ENGINE="openresty"; DISPLAY_ENGINE="OpenResty"; echo -e "${GREEN}✅ Selected: OpenResty${NC}"; break ;;
          2) ENGINE="envoy"; DISPLAY_ENGINE="Envoy Proxy"; echo -e "${GREEN}✅ Selected: Envoy Proxy${NC}"; break ;;
          3) ENGINE="haproxy"; DISPLAY_ENGINE="HAProxy"; echo -e "${GREEN}✅ Selected: HAProxy${NC}"; break ;;
          *) echo -e "${RED}Enter 1, 2, or 3 only${NC}" ;;
      esac
  done

  # 🏷️ GENERATE SERVICE NAME WITH ENGINE INCLUDED
  RAND=$(openssl rand -hex 3)
  CLOUD_RUN_SERVICE_NAME="gcp-xray-${ENGINE}-$RAND"

  echo -e "\n${CYAN}=========================================${NC}"
  echo -e "${GREEN}          BILLING MODE${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${YELLOW}Instance-Based = Stable, No Throttling${NC}"
  echo "1) Request-Based  |  2) Instance-Based"
  while true; do
      read -p "Select [1-2]: " BILLING_CHOICE
      case $BILLING_CHOICE in
          1) BILLING_MODE="request"; BILLING_FLAG="--cpu-throttling"; break ;;
          2) BILLING_MODE="instance"; BILLING_FLAG="--no-cpu-throttling"; break ;;
          *) echo -e "${RED}Enter 1 or 2 only${NC}" ;;
      esac
  done

  echo -e "\n${CYAN}=========================================${NC}"
  echo -e "${GREEN}      RESOURCE CONFIG MODE${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${GREEN}1) AUTO PRESETS  |  Recommended${NC}"
  echo -e "${YELLOW}2) MANUAL SETUP  |  Full Memory & vCPU Range${NC}"
  while true; do
      read -p "Select Mode [1-2]: " RES_MODE
      case $RES_MODE in
          1)
              echo -e "\n${CYAN}--- AUTO PRESETS ---${NC}"
              echo "1) Basic:    1Gi RAM + 1 vCPU"
              echo "2) Balanced: 2Gi RAM + 2 vCPU ✅"
              echo "3) Turbo:    4Gi RAM + 2 vCPU (High Concurrency)"
              read -p "Choose preset [1-3]: " AUTO_CHOICE
              case $AUTO_CHOICE in
                  1) MEMORY="1Gi"; CPU="1" ;;
                  2) MEMORY="2Gi"; CPU="2" ;;
                  3) MEMORY="4Gi"; CPU="2" ;;
                  *) echo -e "${YELLOW}Using Balanced preset${NC}"; MEMORY="2Gi"; CPU="2" ;;
              esac
              echo -e "${GREEN}✅ Applied Preset: $MEMORY | $CPU vCPU${NC}"
              
              # Hardcoded scaling for Auto Presets
              MIN_INST=1
              MAX_INST=5
              CONCURRENCY=200
              TIMEOUT=3600
              break
              ;;
          2)
              echo -e "\n${YELLOW}--- MANUAL SETUP ---${NC}"
              echo "Select Memory:"
              echo "1) 256Mi   2) 512Mi   3) 1Gi   4) 2Gi"
              echo "5) 4Gi     6) 8Gi     7) 16Gi  8) Custom input"
              read -p "Select Memory [1-8]: " MEM
              case $MEM in
                  1) MEMORY="256Mi" ;;
                  2) MEMORY="512Mi" ;;
                  3) MEMORY="1Gi" ;;
                  4) MEMORY="2Gi" ;;
                  5) MEMORY="4Gi" ;;
                  6) MEMORY="8Gi" ;;
                  7) MEMORY="16Gi" ;;
                  8) read -p "Type custom memory: " MEMORY ;;
                  *) MEMORY="1Gi" ;;
              esac

              echo -e "\nSelect vCPU:"
              echo "1) 1 vCPU   2) 2 vCPU   3) 4 vCPU   4) 8 vCPU   5) Custom input"
              read -p "Select vCPU [1-5]: " CPU_SEL
              case $CPU_SEL in
                  1) CPU="1" ;;
                  2) CPU="2" ;;
                  3) CPU="4" ;;
                  4) CPU="8" ;;
                  5) read -p "Type custom vCPU: " CPU ;;
                  *) CPU="1" ;;
              esac

              echo -e "${GREEN}✅ Custom Selected: $MEMORY RAM | $CPU vCPU${NC}"

              # Manual scaling configuration prompts
              echo -e "\n${CYAN}=========================================${NC}"
              echo -e "${GREEN}    PERFORMANCE & SCALING CONFIGURATION  ${NC}"
              echo -e "${CYAN}=========================================${NC}"
              read -p "Min Instances [Default: 0]: " MIN_INST
              MIN_INST=${MIN_INST:-0}

              read -p "Max Instances [Default: 1]: " MAX_INST
              MAX_INST=${MAX_INST:-1}

              read -p "Concurrency / Max Connections [Default: 1000]: " CONCURRENCY
              CONCURRENCY=${CONCURRENCY:-1000}

              read -p "Timeout in seconds [Default: 3600]: " TIMEOUT
              TIMEOUT=${TIMEOUT:-3600}

              echo -e "${GREEN}✅ Config Set: Min: $MIN_INST | Max: $MAX_INST | Concurrency: $CONCURRENCY | Timeout: ${TIMEOUT}s${NC}"
              break
              ;;
          *) echo -e "${RED}Enter 1 or 2 only${NC}" ;;
      esac
  done

  BUILD_DIR=$(mktemp -d)
  trap 'rm -rf "$BUILD_DIR"' EXIT
  cd "$BUILD_DIR" || exit 1

  clear
  echo ""
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${GREEN}🚀 GCP-XRAY DEPLOYER | MULTI-ENGINE SETUP${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${GREEN}✅ Project:${NC} $PROJECT_ID"
  echo -e "${GREEN}✅ Region:${NC} $REGION"
  echo -e "${GREEN}✅ Service Name:${NC} $CLOUD_RUN_SERVICE_NAME"
  echo -e "${GREEN}✅ Scaling:${NC} Min: $MIN_INST | Max: $MAX_INST"
  echo -e "${GREEN}✅ Performance:${NC} Concurrency: $CONCURRENCY | Timeout: ${TIMEOUT}s"
  echo ""

  cat > config.json <<'EOF'
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": ["8.8.8.8", "8.8.4.4"],
    "strategy": "UseIPv4"
  },
  "policy": {
    "levels": {
      "0": {
        "handshake": 2,
        "connIdle": 3600,
        "bufferSize": 1048576
      }
    }
  },
  "inbounds": [
    {
      "tag": "trojan-ws",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": { "clients": [{"password": "gcp-xray", "level": 0}] },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"], "routeOnly": true },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan-ws" },
        "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "tcpKeepAliveIdle": 300, "tcpKeepAliveInterval": 30 }
      }
    },
    {
      "tag": "vless-ws",
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [{"id": "a1b2c3d4-5678-40ef-98ab-cdef01234567", "level": 0}], "decryption": "none" },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"], "routeOnly": true },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless-ws" },
        "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "tcpKeepAliveIdle": 300, "tcpKeepAliveInterval": 30 }
      }
    },
    {
      "tag": "trojan-xhttp",
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": { "clients": [{"password": "gcp-xray", "level": 0}] },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"], "routeOnly": true },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": { "path": "/trojan-xhttp" },
        "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "tcpKeepAliveIdle": 300, "tcpKeepAliveInterval": 30 }
      }
    },
    {
      "tag": "vless-xhttp",
      "port": 10004,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [{"id": "a1b2c3d4-5678-40ef-98ab-cdef01234567", "level": 0}], "decryption": "none" },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"], "routeOnly": true },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": { "path": "/vless-xhttp" },
        "sockopt": { "tcpNoDelay": true, "tcpFastOpen": true, "tcpKeepAliveIdle": 300, "tcpKeepAliveInterval": 30 }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIPv4" } },
    { "protocol": "blackhole", "tag": "blocked", "settings": { "response": { "type": "none" } } }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked" },
      { "type": "field", "inboundTag": ["trojan-ws", "vless-ws", "trojan-xhttp", "vless-xhttp"], "outboundTag": "direct" }
    ]
  }
}
EOF

  DECOY_HTML='<!DOCTYPE html><html><head><title>System Status</title><style>body{font-family:sans-serif;background:#0d1117;color:#c9d1d9;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;text-align:center;}h1{color:#58a6ff;font-size:24px;}p{color:#8b949e;}</style></head><body><div><h1>Welcome to my '"$DISPLAY_ENGINE"' cloud application gateway.</h1><p>Everything is operational.</p></div></body></html>'

  if [ "$ENGINE" = "openresty" ]; then
    cat > nginx.conf <<EOF
worker_processes auto;
worker_rlimit_nofile 10240;
events { worker_connections 4096; use epoll; multi_accept on; }
http {
  include mime.types;
  default_type application/octet-stream;
  sendfile on; tcp_nodelay on; tcp_nopush on;
  keepalive_timeout 3600; keepalive_requests 100000;
  client_max_body_size 0;
  proxy_buffering off; proxy_request_buffering off;
  proxy_http_version 1.1; proxy_connect_timeout 10s;
  server {
    listen 8080;
    server_name _;
    location /health { return 200 "OK\n"; add_header Content-Type text/plain; }
    location / {
      default_type text/html;
      return 200 '$DECOY_HTML';
    }
    location /trojan-ws {
      proxy_pass http://127.0.0.1:10001;
      proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
      proxy_read_timeout 3600s; proxy_send_timeout 3600s;
    }
    location /vless-ws {
      proxy_pass http://127.0.0.1:10002;
      proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
      proxy_read_timeout 3600s; proxy_send_timeout 3600s;
    }
    location /trojan-xhttp {
      proxy_pass http://127.0.0.1:10003;
      proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
      proxy_read_timeout 3600s; proxy_send_timeout 3600s;
    }
    location /vless-xhttp {
      proxy_pass http://127.0.0.1:10004;
      proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
      proxy_read_timeout 3600s; proxy_send_timeout 3600s;
    }
  }
}
EOF
    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/xray run -c /etc/xray.json &
sleep 2
exec /usr/local/openresty/bin/openresty -g 'daemon off;'
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip ca-certificates
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && unzip -q xray.zip xray geosite.dat geoip.dat && chmod +x xray
FROM openresty/openresty:alpine-fat
COPY --from=builder /xray /usr/local/bin/xray
COPY --from=builder /geosite.dat /usr/local/share/xray/
COPY --from=builder /geoip.dat /usr/local/share/xray/
COPY config.json /etc/xray.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/xray /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF

  elif [ "$ENGINE" = "envoy" ]; then
    cat > envoy.yaml <<EOF
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8080
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          codec_type: AUTO
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match: { prefix: "/health" }
                direct_response: { status: 200, body: { inline_string: "OK\n" } }
              - match: { prefix: "/trojan-ws" }
                route: { cluster: trojan_cluster, timeout: 3600s, upgrade_configs: [{ upgrade_type: "websocket" }] }
              - match: { prefix: "/vless-ws" }
                route: { cluster: vless_cluster, timeout: 3600s, upgrade_configs: [{ upgrade_type: "websocket" }] }
              - match: { prefix: "/trojan-xhttp" }
                route: { cluster: trojan_xhttp_cluster, timeout: 3600s }
              - match: { prefix: "/vless-xhttp" }
                route: { cluster: vless_xhttp_cluster, timeout: 3600s }
              - match: { prefix: "/" }
                direct_response:
                  status: 200
                  body: { inline_string: '$DECOY_HTML' }
                  response_headers_to_add:
                  - header:
                      key: "content-type"
                      value: "text/html"
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  clusters:
  - name: trojan_cluster
    connect_timeout: 10s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: trojan_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address: { address: 127.0.0.1, port_value: 10001 }
  - name: vless_cluster
    connect_timeout: 10s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: vless_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address: { address: 127.0.0.1, port_value: 10002 }
  - name: trojan_xhttp_cluster
    connect_timeout: 10s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: trojan_xhttp_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address: { address: 127.0.0.1, port_value: 10003 }
  - name: vless_xhttp_cluster
    connect_timeout: 10s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: vless_xhttp_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address: { address: 127.0.0.1, port_value: 10004 }
EOF
    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/xray run -c /etc/xray.json &
sleep 2
exec envoy -c /etc/envoy.yaml
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip ca-certificates
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && unzip -q xray.zip xray geosite.dat geoip.dat && chmod +x xray
FROM envoyproxy/envoy:v1.30-latest
COPY --from=builder /xray /usr/local/bin/xray
COPY --from=builder /geosite.dat /usr/local/share/xray/
COPY --from=builder /geoip.dat /usr/local/share/xray/
COPY config.json /etc/xray.json
COPY envoy.yaml /etc/envoy.yaml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/xray /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF

  elif [ "$ENGINE" = "haproxy" ]; then
    cat > haproxy.cfg <<EOF
global
    log stdout format raw local0
    maxconn 10000

defaults
    log global
    mode http
    timeout connect 10s
    timeout client 3600s
    timeout server 3600s

frontend main
    bind *:8080
    acl is_health path /health
    acl is_trojan path_beg /trojan-ws
    acl is_vless path_beg /vless-ws
    acl is_trojan_xhttp path_beg /trojan-xhttp
    acl is_vless_xhttp path_beg /vless-xhttp

    use_backend health_backend if is_health
    use_backend trojan_backend if is_trojan
    use_backend vless_backend if is_vless
    use_backend trojan_xhttp_backend if is_trojan_xhttp
    use_backend vless_xhttp_backend if is_vless_xhttp
    default_backend default_backend

backend health_backend
    http-request return status 200 content-type "text/plain" string "OK\n"

backend default_backend
    http-request return status 200 content-type "text/html" string '$DECOY_HTML'

backend trojan_backend
    server xray1 127.0.0.1:10001

backend vless_backend
    server xray2 127.0.0.1:10002

backend trojan_xhttp_backend
    server xray3 127.0.0.1:10003

backend vless_xhttp_backend
    server xray4 127.0.0.1:10004
EOF
    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/xray run -c /etc/xray.json &
sleep 2
exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg -db
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip ca-certificates
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && unzip -q xray.zip xray geosite.dat geoip.dat && chmod +x xray
FROM haproxy:2.8-alpine
COPY --from=builder /xray /usr/local/bin/xray
COPY --from=builder /geosite.dat /usr/local/share/xray/
COPY --from=builder /geoip.dat /usr/local/share/xray/
COPY config.json /etc/xray.json
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY entrypoint.sh /entrypoint.sh
USER root
RUN chmod +x /usr/local/bin/xray /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF
  fi

  echo -e "${CYAN}🔨 Building image ($ENGINE engine)...${NC}"
  gcloud builds submit --project="$PROJECT_ID" --tag gcr.io/$PROJECT_ID/$CLOUD_RUN_SERVICE_NAME . --quiet

  echo -e "${CYAN}🚀 Deploying to Cloud Run...${NC}"
  gcloud run deploy "$CLOUD_RUN_SERVICE_NAME" \
    --image gcr.io/$PROJECT_ID/$CLOUD_RUN_SERVICE_NAME \
    --project="$PROJECT_ID" --platform managed --region "$REGION" --allow-unauthenticated \
    --port 8080 --memory "$MEMORY" --cpu "$CPU" --concurrency "$CONCURRENCY" \
    --timeout "$TIMEOUT" --min-instances "$MIN_INST" --max-instances "$MAX_INST" \
    --session-affinity \
    --execution-environment gen2 $BILLING_FLAG --cpu-boost --quiet

  CLOUD_RUN_URL=$(gcloud run services describe "$CLOUD_RUN_SERVICE_NAME" --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')
  DOMAIN=$(echo "$CLOUD_RUN_URL" | sed 's|https://||')
  CANONICAL_LINK="https://$DOMAIN"

  clear
  echo -e "\n${CYAN}=========================================${NC}"
  echo -e "${GREEN}✅ MULTI-ENGINE-GCP-XRAY DEPLOYMENT SUCCESS! (${ENGINE^^})${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${GREEN}🔗 SHORT LINK:${NC} $CANONICAL_LINK"
  echo -e "${GREEN}🌐 NETMOD HOST:${NC} $DOMAIN"
  echo -e "${GREEN}💚 HEALTH CHECK:${NC} $CANONICAL_LINK/health"
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${YELLOW}📝 AVAILABLE ENDPOINTS:${NC}"
  echo -e "   - WebSocket: /trojan-ws, /vless-ws"
  echo -e "   - XHTTP:     /trojan-xhttp, /vless-xhttp"

  read -p $'\nPress [Enter] to return to Main Menu...'
}

while true; do
  clear
  echo "======================================"
  echo "  MULTI-WS-XHTTP-GCP-XRAY DEPLOYER MENU    "
  echo "======================================"
  echo "1) Deploy New GCP-XRAY Service"
  echo "2) List All Services & FULL DETAILS"
  echo "3) Exit Script"
  echo "======================================"
  read -p "Select Option [1-3]: " MENU_CHOICE

  case $MENU_CHOICE in
    1) deploy_new_service ;;
    2) list_deployed_services ;;
    3) echo -e "\n👋 Goodbye!"; exit 0 ;;
    *) echo -e "${RED}❌ Enter 1/2/3 only${NC}"; sleep 2 ;;
  esac
done
