#!/bin/bash
set -e

# 定义Nginx虚拟主机配置文件路径
VHOST_CONF="/etc/nginx/conf.d/vhost.conf"

# 清空原有配置，避免残留
> ${VHOST_CONF}

# 检查环境变量是否必传，无默认值（强制用户指定）
if [ -z "${proxy_pass}" ] || [ -z "${server_name}" ]; then
    echo "ERROR: 必须设置 proxy_pass 和 server_name 环境变量！"
    echo "示例: -e proxy_pass='http://backend1:80,http://backend2:80' -e server_name='domain1.com,domain2.com'"
    exit 1
fi

# 将环境变量按逗号分割为数组（处理多值场景）
IFS=',' read -ra PROXY_PASS_ARRAY <<< "${proxy_pass}"
IFS=',' read -ra SERVER_NAME_ARRAY <<< "${server_name}"

# 验证数组长度一致（核心校验）
if [ ${#PROXY_PASS_ARRAY[@]} -ne ${#SERVER_NAME_ARRAY[@]} ]; then
    echo "ERROR: proxy_pass 和 server_name 的值数量不匹配！"
    echo "proxy_pass 数量: ${#PROXY_PASS_ARRAY[@]}"
    echo "server_name 数量: ${#SERVER_NAME_ARRAY[@]}"
    exit 1
fi

# 生成通用的Nginx vhost配置（适配任意后端）
echo "# 自动生成的ModSecurity防护反向代理配置 - $(date)" >> ${VHOST_CONF}
echo "" >> ${VHOST_CONF}

# 遍历数组，逐一生成server块
for i in "${!PROXY_PASS_ARRAY[@]}"; do
    # 清理值前后的空格（容错处理）
    current_proxy=$(echo "${PROXY_PASS_ARRAY[$i]}" | xargs)
    current_server=$(echo "${SERVER_NAME_ARRAY[$i]}" | xargs)

    # 生成通用的server配置（无WordPress专属配置）
    cat << EOF >> ${VHOST_CONF}
server {
    listen 80;
    server_name ${current_server};

    # 启用ModSecurity WAF防护（核心）
    modsecurity on;
    modsecurity_rules_file /etc/modsecurity.d/modsecurity.conf;

    # 通用反向代理配置（适配任意后端）
    location / {
        proxy_pass ${current_proxy};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    # 通用静态资源缓存（适配所有后端）
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        proxy_pass ${current_proxy};
        proxy_set_header Host \$host;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
    }

    # 通用上传大小限制（可根据需求调整）
    client_max_body_size 64M;
}

EOF
done

# 输出生成的配置（调试用，可注释）
echo "✅ 成功生成vhost.conf："
cat ${VHOST_CONF}

# 执行容器启动命令（启动Nginx）
exec "$@"
