# 基于官方的owasp/modsecurity-crs nginx版本
FROM owasp/modsecurity-crs:nginx

# 切换到root用户执行系统级操作（核心修复）
USER root

# 仅安装必要的基础工具，最小化镜像
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# 创建配置生成脚本
COPY generate_vhost.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/generate_vhost.sh

# 清空默认的default.conf，避免冲突（核心）
RUN rm -f /etc/nginx/conf.d/default.conf

# 可选：切回非root用户（保持镜像安全最佳实践）
USER nginx

# 启动逻辑：先生成配置，再启动nginx
ENTRYPOINT ["/usr/local/bin/generate_vhost.sh"]
CMD ["nginx", "-g", "daemon off;"]
