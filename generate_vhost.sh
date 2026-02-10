#!/bin/bash
set -e

# 定义Nginx虚拟主机配置文件路径
VHOST_CONF="/etc/nginx/conf.d/vhost.conf"

# ======================== 第一步：必传参数校验 ========================
# 检查proxy_pass和server_name是否传入，无值则直接退出
if [ -z "${proxy_pass}" ] || [ -z "${server_name}" ]; then
    echo -e "\033[31mERROR: 必须设置 proxy_pass 和 server_name 环境变量！\033[0m"
    echo "示例: -e proxy_pass='http://backend1:80,http://backend2:80' -e server_name='domain1.com,domain2.com'"
    exit 1  # 退出码1，终止所有操作
fi

# ======================== 第二步：数量匹配校验 ========================
# 将环境变量按逗号分割为数组
IFS=',' read -ra PROXY_PASS_ARRAY <<< "${proxy_pass}"
IFS=',' read -ra SERVER_NAME_ARRAY <<< "${server_name}"

# 清理数组中的空值（处理用户误输入多逗号的情况，如"domain1.com,,domain2.com"）
PROXY_PASS_ARRAY=($(printf "%s\n" "${PROXY_PASS_ARRAY[@]}" | awk 'NF'))
SERVER_NAME_ARRAY=($(printf "%s\n" "${SERVER_NAME_ARRAY[@]}" | awk 'NF'))

# 校验数量是否一致，不一致则立即退出
if [ ${#PROXY_PASS_ARRAY[@]} -ne ${#SERVER_NAME_ARRAY[@]} ]; then
    echo -e "\033[31mERROR: proxy_pass 和 server_name 数量不匹配！\033[0m"
    echo -e "→ proxy_pass 解析出的地址数量：\033[33m${#PROXY_PASS_ARRAY[@]}\033[0m (值：${PROXY_PASS_ARRAY[*]})"
    echo -e "→ server_name 解析出的域名数量：\033[33m${#SERVER_NAME_ARRAY[@]}\033[0m (值：${SERVER_NAME_ARRAY[*]})"
    echo -e "\033[31m终止配置文件创建和Nginx启动！\033[0m"
    exit 2  # 退出码2，标识数量不匹配错误
fi

# ======================== 第三步：配置生成（仅校验通过后执行） ========================
# 清空原有配置
> ${VHOST_CONF}

# 生成通用的Nginx vhost配置
echo "# 自动生成的ModSecurity防护反向代理配置 - $(date)" >> ${VHOST_CONF}
echo "" >> ${VHOST_CONF}

# 遍历数组生成server块
for i in "${!PROXY_PASS_ARRAY[@]}"; do
    current_proxy=$(echo "${PROXY_PASS_ARRAY[$i]}" | xargs)
    current_server=$(echo "${SERVER_NAME_ARRAY[$i]}" | xargs)

    cat << EOF >> ${VHOST_CONF}
server {
    listen 80;
    server_name ${current_server};

    # 启用ModSecurity WAF防护
    modsecurity on;
    modsecurity_rules_file /etc/modsecurity.d/modsecurity.conf;

    # 通用反向代理配置
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

    # 通用静态资源缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        proxy_pass ${current_proxy};
        proxy_set_header Host \$host;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
    }

    client_max_body_size 64M;
}

EOF
done

# 输出生成结果
echo -e "\033[32m✅ 成功生成vhost.conf，配置如下：\033[0m"
cat ${VHOST_CONF}

# ======================== 第四步：启动Nginx（仅配置生成成功后执行） ========================
exec "$@"
