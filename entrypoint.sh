#!/usr/bin/env bash

# 默认各参数值，请自行修改.(注意:伪装路径不需要 / 符号开始,为避免不必要的麻烦,请不要使用特殊符号.)
PORT=${PORT:-'8080'}
UUID=${UUID:-'de04add9-5c68-8bab-950c-08cd5320df18'}
WSPATH=${WSPATH:-'argo'}
ARGO_DOMAIN=${ARGO_DOMAIN:-''}
ARGO_AUTH=${ARGO_TOKEN:-''}

# 生成 Sing-box 配置文件
cat > config.json << EOF
{
    "log":{
        "disabled": true,
        "level": "info",
        "timestamp": true
    },
    "inbounds":[
        {
            "port":${PORT},
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "flow":"xtls-rprx-direct"
                    }
                ],
                "decryption":"none",
                "fallbacks":[
                    {
                        "dest":3001
                    },
                    {
                        "path":"/${WSPATH}-vless",
                        "dest":3002
                    },
                    {
                        "path":"/${WSPATH}-vmess",
                        "dest":3003
                    },
                    {
                        "path":"/${WSPATH}-trojan",
                        "dest":3004
                    }
                ]
            },
            "streamSettings":{
                "network":"tcp"
            }
        },
        {
            "port":3001,
            "listen":"127.0.0.1",
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}"
                    }
                ],
                "decryption":"none"
            },
            "streamSettings":{
                "network":"ws",
                "security":"none"
            }
        },
        {
            "port":3002,
            "listen":"127.0.0.1",
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "level":0,
                        "email":"argo@xray"
                    }
                ],
                "decryption":"none"
            },
            "streamSettings":{
                "network":"ws",
                "security":"none",
                "wsSettings":{
                    "path":"/${WSPATH}-vless"
                }
            },
            "sniffing":{
                "enabled":true,
                "destOverride":[
                    "http",
                    "tls",
                    "quic"
                ],
                "metadataOnly":false
            }
        },
        {
            "port":3003,
            "listen":"127.0.0.1",
            "protocol":"vmess",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "alterId":0
                    }
                ]
            },
            "streamSettings":{
                "network":"ws",
                "wsSettings":{
                    "path":"/${WSPATH}-vmess"
                }
            },
            "sniffing":{
                "enabled":true,
                "destOverride":[
                    "http",
                    "tls",
                    "quic"
                ],
                "metadataOnly":false
            }
        },
        {
            "port":3004,
            "listen":"127.0.0.1",
            "protocol":"trojan",
            "settings":{
                "clients":[
                    {
                        "password":"${UUID}"
                    }
                ]
            },
            "streamSettings":{
                "network":"ws",
                "security":"none",
                "wsSettings":{
                    "path":"/${WSPATH}-trojan"
                }
            },
            "sniffing":{
                "enabled":true,
                "destOverride":[
                    "http",
                    "tls",
                    "quic"
                ],
                "metadataOnly":false
            }
        }
    ],
    "dns":{
        "servers":[
            "https+local://8.8.8.8/dns-query"
        ]
    },
    "outbounds":[
        {
            "protocol":"freedom"
        }
    ]
}
EOF

argo_configure() {
  if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    echo $ARGO_AUTH > tunnel.json
    cat > tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$ARGO_AUTH")
credentials-file: tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$vmess_port
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
  fi
}

# 下载并运行 Argo
RANDOM_NAME=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 7)
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
mv cloudflared-linux-amd64 ${RANDOM_NAME}
chmod +x ${RANDOM_NAME}
if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
    #args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
    args="tunnel --no-autoupdate run --token ${ARGO_AUTH}"
elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    args="tunnel --edge-ip-version auto --config tunnel.yml run"
else
    args="tunnel --url http://localhost:$vmess_port --no-autoupdate --logfile argo.log --loglevel info"
fi
nohup ./${RANDOM_NAME} $args >/dev/null 2>&1 &

get_argodomain() {
  if [[ -n $ARGO_AUTH ]]; then
    echo "$ARGO_DOMAIN"
  else
    argodomain=$(cat argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    echo "$argodomain"
  fi
}

# 下载 Xray，并伪装 xray 执行文件
RANDOM_NAME=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 6)
#wget -O temp.tar.gz https://github.com/SagerNet/sing-box/releases/download/v1.10.7/sing-box-1.10.7-linux-amd64.tar.gz
#tar -xzvf  temp.tar.gz
#mv sing-box-1.10.7-linux-amd64/sing-box ./${RANDOM_NAME}
#rm -f temp.tar.gz
wget -O temp.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip temp.zip xray geosite.dat geoip.dat
mv xray ${RANDOM_NAME}
rm -f temp.zip

# 显示节点信息
sleep 15
#ARGO=$(get_argodomain)
ARGO=${KOYEB_PUBLIC_DOMAIN}
cat > list << EOF
*******************************************
V2-rayN:
----------------------------
vless://${UUID}@www.digitalocean.com:443?encryption=none&security=tls&sni=${ARGO}&type=ws&host=${ARGO}&path=%2F${WSPATH}-vless#Argo-Vless
----------------------------
vmess://$(echo "{ \"v\": \"2\", \"ps\": \"Argo-Vmess\", \"add\": \"www.digitalocean.com\", \"port\": \"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO}\", \"path\": \"${WSPATH}-vmess\", \"tls\": \"tls\", \"sni\": \"${ARGO}\", \"alpn\": \"\" }" | base64 -w0)
----------------------------
trojan://${UUID}@www.digitalocean.com:443?security=tls&sni=${ARGO}&type=ws&host=${ARGO}&path=%2F${WSPATH}-trojan#Argo-Trojan
*******************************************
小火箭:
----------------------------
vless://${UUID}@www.digitalocean.com:443?encryption=none&security=tls&type=ws&host=${ARGO}&path=/${WSPATH}-vless&sni=${ARGO}#Argo-Vless
----------------------------
vmess://$(echo "none:${UUID}@www.digitalocean.com:443" | base64 -w0)?remarks=Argo-Vmess&obfsParam=${ARGO}&path=/${WSPATH}-vmess&obfs=websocket&tls=1&peer=${ARGO}&alterId=0
----------------------------
trojan://${UUID}@www.digitalocean.com:443?peer=${ARGO}&plugin=obfs-local;obfs=websocket;obfs-host=${ARGO};obfs-uri=/${WSPATH}-trojan#Argo-Trojan
*******************************************
Clash:
----------------------------
- {name: Argo-Vless, type: vless, server: www.digitalocean.com, port: 443, uuid: ${UUID}, tls: true, servername: ${ARGO}, skip-cert-verify: false, network: ws, ws-opts: {path: /${WSPATH}-vless, headers: { Host: ${ARGO}}}, udp: true}
----------------------------
- {name: Argo-Vmess, type: vmess, server: www.digitalocean.com, port: 443, uuid: ${UUID}, alterId: 0, cipher: none, tls: true, skip-cert-verify: true, network: ws, ws-opts: {path: /${WSPATH}-vmess, headers: {Host: ${ARGO}}}, udp: true}
----------------------------
- {name: Argo-Trojan, type: trojan, server: www.digitalocean.com, port: 443, password: ${UUID}, udp: true, tls: true, sni: ${ARGO}, skip-cert-verify: false, network: ws, ws-opts: { path: /${WSPATH}-trojan, headers: { Host: ${ARGO} } } }
*******************************************
EOF

echo -e "\n↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓\n"
cat list
echo -e "\n 节点保存在文件: /app/list \n"
echo -e "\n↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑\n"

# 运行 Xray
nohup ./${RANDOM_NAME} run -config config.json >/dev/null 2>&1 &

