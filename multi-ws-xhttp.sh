#!/bin/bash
set -euo pipefail

# =========================================
# 🚀 GCP-XRAY MULTI-ENGINE DEPLOYER — FIXED + BEAUTIFUL DECOY
# ✅ ENGINES: OPENRESTY, ENVOY, HAPROXY
# ✅ PROTOCOLS: WS & XHTTP
# ✅ INTEGRATED DNS & ADBLOCK ROUTING
# ✅ FIXED: Xray startup, assets path, entrypoint
# ✅ BEAUTIFUL RESPONSIVE DECOY PAGE
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
  sudo apt update -qq && sudo apt install -y -qq jq netcat-openbsd || {
    echo -e "${RED}❌ Failed to install jq/netcat!${NC}"
    exit 1
  }
  echo -e "${GREEN}✅ jq & netcat installed successfully!${NC}"
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
    ["us-east1"]="South Carolina, US 🇺🇸"
    ["us-east4"]="N. Virginia, US 🇺🇸"
    ["us-west1"]="Oregon, US 🇺🇸"
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
  read -p "Press [Enter] to return..." </dev/tty
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
  echo "7) asia-northeast1  (Tokyo, Japan 🇯🇵)"
  echo "8) asia-northeast3  (Seoul, South Korea 🇰🇷)"
  echo "9) asia-south1      (Mumbai, India 🇮🇳)"
  echo ""
  echo "--- Europe ---"
  echo "10) europe-west1    (Belgium 🇧🇪)"
  echo "11) europe-west4    (Netherlands 🇳🇱)"
  echo "12) europe-west9    (Paris, France 🇫🇷)"
  echo ""
  echo "0) Enter custom region code"
  echo ""
  read -p "Enter region number: " REGION_NUM </dev/tty
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
    0) read -p "Type full region code: " REGION </dev/tty ;;
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
      read -p "Press [Enter] to return..." </dev/tty
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
      read -p "Select Engine [1-3]: " ENGINE_CHOICE </dev/tty
      case $ENGINE_CHOICE in
          1) ENGINE="openresty"; DISPLAY_ENGINE="OpenResty"; echo -e "${GREEN}✅ Selected: OpenResty${NC}"; break ;;
          2) ENGINE="envoy"; DISPLAY_ENGINE="Envoy Proxy"; echo -e "${GREEN}✅ Selected: Envoy Proxy${NC}"; break ;;
          3) ENGINE="haproxy"; DISPLAY_ENGINE="HAProxy"; echo -e "${GREEN}✅ Selected: HAProxy${NC}"; break ;;
          *) echo -e "${RED}Enter 1, 2, or 3 only${NC}" ;;
      esac
  done

  RAND=$(openssl rand -hex 3)
  CLOUD_RUN_SERVICE_NAME="gcp-xray-${ENGINE}-$RAND"

  echo -e "\n${CYAN}=========================================${NC}"
  echo -e "${GREEN}          BILLING MODE${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${YELLOW}Instance-Based = Stable, No Throttling${NC}"
  echo "1) Request-Based  |  2) Instance-Based"
  while true; do
      read -p "Select [1-2]: " BILLING_CHOICE </dev/tty
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
      read -p "Select Mode [1-2]: " RES_MODE </dev/tty
      case $RES_MODE in
          1)
              echo -e "\n${CYAN}--- AUTO PRESETS ---${NC}"
              echo "1) Basic:    1Gi RAM + 1 vCPU"
              echo "2) Balanced: 2Gi RAM + 2 vCPU ✅"
              echo "3) Turbo:    4Gi RAM + 2 vCPU (High Concurrency)"
              read -p "Choose preset [1-3]: " AUTO_CHOICE </dev/tty
              case $AUTO_CHOICE in
                  1) MEMORY="1Gi"; CPU="1" ;;
                  2) MEMORY="2Gi"; CPU="2" ;;
                  3) MEMORY="4Gi"; CPU="2" ;;
                  *) echo -e "${YELLOW}Using Balanced preset${NC}"; MEMORY="2Gi"; CPU="2" ;;
              esac
              echo -e "${GREEN}✅ Applied Preset: $MEMORY | $CPU vCPU${NC}"
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
              read -p "Select Memory [1-8]: " MEM </dev/tty
              case $MEM in
                  1) MEMORY="256Mi" ;;
                  2) MEMORY="512Mi" ;;
                  3) MEMORY="1Gi" ;;
                  4) MEMORY="2Gi" ;;
                  5) MEMORY="4Gi" ;;
                  6) MEMORY="8Gi" ;;
                  7) MEMORY="16Gi" ;;
                  8) read -p "Type custom memory: " MEMORY </dev/tty ;;
                  *) MEMORY="1Gi" ;;
              esac
              echo -e "\nSelect vCPU:"
              echo "1) 1 vCPU   2) 2 vCPU   3) 4 vCPU   4) 8 vCPU   5) Custom input"
              read -p "Select vCPU [1-5]: " CPU_SEL </dev/tty
              case $CPU_SEL in
                  1) CPU="1" ;;
                  2) CPU="2" ;;
                  3) CPU="4" ;;
                  4) CPU="8" ;;
                  5) read -p "Type custom vCPU: " CPU </dev/tty ;;
                  *) CPU="1" ;;
              esac
              echo -e "${GREEN}✅ Custom Selected: $MEMORY RAM | $CPU vCPU${NC}"
              echo -e "\n${CYAN}=========================================${NC}"
              echo -e "${GREEN}    PERFORMANCE & SCALING CONFIGURATION${NC}"
              echo -e "${CYAN}=========================================${NC}"
              read -p "Min Instances [Default: 0]: " MIN_INST </dev/tty
              MIN_INST=${MIN_INST:-0}
              read -p "Max Instances [Default: 1]: " MAX_INST </dev/tty
              MAX_INST=${MAX_INST:-1}
              read -p "Concurrency / Max Connections [Default: 1000]: " CONCURRENCY </dev/tty
              CONCURRENCY=${CONCURRENCY:-1000}
              read -p "Timeout in seconds [Default: 3600]: " TIMEOUT </dev/tty
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

  # ==============================================
  # ✅ FIXED CONFIG.JSON — added assets section
  # ==============================================
  cat > config.json <<'EOF'
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": ["8.8.8.8", "8.8.4.4"],
    "strategy": "UseIPv4"
  },
  "assets": {
    "directory": "/usr/local/share/xray/"
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

  # ==============================================
  # 🎨 BEAUTIFUL DECOY HTML — Clean & Modern
  # ==============================================
  DECOY_HTML='<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>System Status</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:linear-gradient(135deg,#0f172a 0%,#1e293b 100%);color:#e2e8f0;min-height:100vh;display:flex;justify-content:center;align-items:center;text-align:center;padding:20px}.container{background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:16px;padding:48px 32px;max-width:420px;width:100%;backdrop-filter:blur(10px);box-shadow:0 8px 32px rgba(0,0,0,0.3)}.icon{font-size:64px;margin-bottom:24px}h1{color:#38bdf8;font-size:22px;font-weight:600;margin-bottom:12px}p{color:#94a3b8;font-size:15px;line-height:1.6;margin-bottom:24px}.status-badge{display:inline-flex;align-items:center;gap:8px;background:rgba(34,197,94,0.15);color:#86efac;padding:10px 20px;border-radius:50px;font-size:14px;font-weight:500}.status-dot{width:10px;height:10px;background:#22c55e;border-radius:50%;animation:pulse 2s infinite}@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.4}}</style></head><body><div class="container"><div class="icon">✅</div><h1>System Operational</h1><p>Welcome to my '"$DISPLAY_ENGINE"' cloud application gateway.<br>All services are running normally.</p><div class="status-badge"><span class="status-dot"></span>Online & Healthy</div></div></body></html>'

  # ==============================================
  # ✅ FIXED ENTRYPOINT — waits for Xray to be ready
  # ==============================================
  cat > entrypoint.sh <<'EOF'
#!/bin/sh
set -e

echo "✅ Starting Xray..."
xray run -c /etc/xray.json &
XRAY_PID=$!

# Wait up to 15s for Xray to be ready
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if nc -z 127.0.0.1 10001 2>/dev/null; then
    echo "✅ Xray READY on port 10001"
    break
  fi
  echo "⏳ Waiting Xray... ($i/15)"
  sleep 1
done

if ! kill -0 $XRAY_PID 2>/dev/null; then
  echo "❌ Xray CRASHED! Check config.json"
  exit 1
fi

echo "✅ Starting Proxy..."
exec "$@"
EOF
  chmod +x entrypoint.sh

  # ==============================================
  # 🟢 OPENRESTY
  # ==============================================
  if [ "$ENGINE" = "openresty" ]; then
    cat > nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 10240;
    use epoll;
    multi_accept on;
}
http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100000;
    client_max_body_size 4096M;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_connect_timeout 10s;
    proxy_buffering off;
    proxy_request_buffering off;

    server {
        listen 8080;
        server_name _;

        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }

        location /trojan-ws {
            proxy_pass http://127.0.0.1:10001;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 3600s;
        }

        location /vless-ws {
            proxy_pass http://127.0.0.1:10002;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 3600s;
        }

        location /trojan-xhttp {
            proxy_pass http://127.0.0.1:10003;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 3600s;
        }

        location /vless-xhttp {
            proxy_pass http://127.0.0.1:10004;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 3600s;
        }

        location / {
            default_type text/html;
            return 200 'PLACEHOLDER_DECOY';
        }
    }
}
EOF
    sed -i "s|PLACEHOLDER_DECOY|$DECOY_HTML|" nginx.conf

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip ca-certificates
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && \
    unzip -q xray.zip xray geosite.dat geoip.dat && \
    chmod +x xray

FROM openresty/openresty:alpine-fat
COPY --from=builder /xray /usr/local/bin/xray
COPY --from=builder /geosite.dat /usr/local/share/xray/
COPY --from=builder /geoip.dat /usr/local/share/xray/
COPY config.json /etc/xray.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/xray /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh", "/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
EOF

  # ==============================================
  # 🔵 ENVOY
  # ==============================================
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
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match: { prefix: "/health" }
                direct_response: { status: 200, body: { inline_string: "OK\n" } }
              - match: { prefix: "/trojan-ws" }
                route: { cluster: trojan_cluster, upgrade_configs: [{ upgrade_type: "websocket" }], timeout: 3600s }
              - match: { prefix: "/vless-ws" }
                route: { cluster: vless_cluster, upgrade_configs: [{ upgrade_type: "websocket" }], timeout: 3600s }
              - match: { prefix: "/trojan-xhttp" }
                route: { cluster: trojan_xhttp_cluster, timeout: 3600s }
              - match: { prefix: "/vless-xhttp" }
                route: { cluster: vless_xhttp_cluster, timeout: 3600s }
              - match: { prefix: "/" }
                direct_response: { status: 200, body: { inline_string: '$DECOY_HTML' } }
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  clusters:
  - name: trojan_cluster
    connect_timeout: 10s
    type: STRICT_DNS
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
    type: STRICT_DNS
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
    type: STRICT_DNS
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
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: vless_xhttp_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address: { address: 127.0.0.1, port_value: 10004 }
EOF

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip ca-certificates
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && \
    unzip -q xray.zip xray geosite.dat geoip.dat && \
    chmod +x xray

FROM envoyproxy/envoy:v1.30-latest
COPY --from=builder /xray /usr/local/bin/xray
COPY --from=builder /geosite.dat /usr/local/share/xray/
COPY --from=builder /geoip.dat /usr/local/share/xray/
COPY config.json /etc/xray.json
COPY envoy.yaml /etc/envoy.yaml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/xray /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh", "envoy", "-c", "/etc/envoy.yaml"]
EOF

  # ==============================================
  # 🟠 HAPROXY
  # ==============================================
  elif [ "$ENGINE" = "haproxy" ]; then
    cat > haproxy.cfg <<EOF
global
    log stdout format raw local0
    maxconn 10000

defaults
    log global
    mode http
    option httplog
    timeout connect 10s
    timeout client 3600s
    timeout server 3600s

frontend main
    bind *:8080
    mode http

    acl is_health path /health
    acl is_trojan path /trojan-ws
    acl is_vless path /vless-ws
    acl is_trojan_xhttp path /trojan-xhttp
    acl is_vless_xhttp path /vless-xhttp

    http-request return status 200 content-type "text/plain" string "OK\n" if is_health

    use_backend trojan_backend if is_trojan
    use_backend vless_backend if is_vless
    use_backend trojan_xhttp_backend if is_trojan_xhttp
    use_backend vless_xhttp_backend if is_vless_xhttp

    default_backend decoy_backend

backend decoy_backend
    mode http
    http-request return status 200 content-type "text/html" string '$DECOY_HTML'

backend trojan_backend
    mode http
    server xray1 127.0.0.1:10001

backend vless_backend
    mode http
    server xray2 127.0.0.1:10002

backend trojan_xhttp_backend
    mode http
    server xray3 127.0.0.1:10003

backend vless_xhttp_backend
    mode http
    server xray4 127.0.0.1:10004
EOF

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip ca-certificates
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && \
    unzip -q xray.zip xray geosite.dat geoip.dat && \
    chmod +x xray

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
ENTRYPOINT ["/entrypoint.sh", "haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg", "-db"]
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
    --session-affinity --execution-environment gen2 $BILLING_FLAG --cpu-boost --quiet

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
  echo -e "   - Trojan+WS:   $CANONICAL_LINK/trojan-ws"
  echo -e "   - VLESS+WS:    $CANONICAL_LINK/vless-ws"
  echo -e "   - Trojan+XHTTP:$CANONICAL_LINK/trojan-xhttp"
  echo -e "   - VLESS+XHTTP: $CANONICAL_LINK/vless-xhttp"
  echo ""
  echo -e "${CYAN}🔑 CREDENTIALS:${NC}"
  echo -e "   - Trojan Password: gcp-xray"
  echo -e "   - VLESS ID: a1b2c3d4-5678-40ef-98ab-cdef01234567"
  echo -e "   - Decryption: none (VLESS)"
  echo ""
  read -p $'\nPress [Enter] to return to Main Menu...' </dev/tty
}

# ==============================================
# MAIN MENU
# ==============================================
while true; do
  clear
  echo "======================================"
  echo "  MULTI-WS-XHTTP-GCP-XRAY DEPLOYER    "
  echo "       FIXED + BEAUTIFUL DECOY        "
  echo "======================================"
  echo "1) Deploy New GCP-XRAY Service"
  echo "2) List All Services & FULL DETAILS"
  echo "3) Exit Script"
  echo "======================================"
  read -p "Select Option [1-3]: " MENU_CHOICE </dev/tty

  case $MENU_CHOICE in
    1) deploy_new_service ;;
    2) list_deployed_services ;;
    3) echo -e "\n👋 Goodbye!"; exit 0 ;;
    *) echo -e "${RED}❌ Enter 1/2/3 only${NC}"; sleep 2 ;;
  esac
done
