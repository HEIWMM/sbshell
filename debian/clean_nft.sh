echo "开始清除防火墙规则..."
nft flush ruleset

# 写入Docker相关的防火墙规则
cat > /tmp/docker_rules.nft <<EOF
# Warning: table ip nat is managed by iptables-nft, do not touch! 
table ip nat { 
        chain DOCKER { 
                iifname "docker0" counter packets 0 bytes 0 return 
                iifname "br-8bad6f7ab7c0" counter packets 0 bytes 0 return 
                iifname != "docker0" tcp dport 9000 counter packets 0 bytes 0 dnat to 172.17.0.2:9000 
        } 

        chain POSTROUTING { 
                type nat hook postrouting priority srcnat; policy accept; 
                oifname != "docker0" ip saddr 172.17.0.0/16 counter packets 0 bytes 0 masquerade 
                oifname != "br-8bad6f7ab7c0" ip saddr 172.18.0.0/16 counter packets 0 bytes 0 masquerade 
                ip saddr 172.17.0.2 ip daddr 172.17.0.2 tcp dport 9000 counter packets 0 bytes 0 masquerade 
        } 

        chain PREROUTING { 
                type nat hook prerouting priority dstnat; policy accept; 
                fib daddr type local counter packets 5 bytes 354 jump DOCKER 
        } 

        chain OUTPUT { 
                type nat hook output priority -100; policy accept; 
                ip daddr != 127.0.0.0/8 fib daddr type local counter packets 0 bytes 0 jump DOCKER 
        } 
} 
# Warning: table ip filter is managed by iptables-nft, do not touch! 
table ip filter { 
        chain DOCKER { 
                iifname != "docker0" oifname "docker0" ip daddr 172.17.0.2 tcp dport 9000 counter packets 0 bytes 0 accept 
        } 

        chain DOCKER-ISOLATION-STAGE-1 { 
                iifname "docker0" oifname != "docker0" counter packets 0 bytes 0 jump DOCKER-ISOLATION-STAGE-2 
                iifname "br-8bad6f7ab7c0" oifname != "br-8bad6f7ab7c0" counter packets 0 bytes 0 jump DOCKER-ISOLATION-STAGE-2 
                counter packets 0 bytes 0 return 
        } 

        chain DOCKER-ISOLATION-STAGE-2 { 
                oifname "docker0" counter packets 0 bytes 0 drop 
                oifname "br-8bad6f7ab7c0" counter packets 0 bytes 0 drop 
                counter packets 0 bytes 0 return 
        } 

        chain FORWARD { 
                type filter hook forward priority filter; policy accept; 
                counter packets 0 bytes 0 jump DOCKER-USER 
                counter packets 0 bytes 0 jump DOCKER-ISOLATION-STAGE-1 
                oifname "docker0" ct state related,established counter packets 0 bytes 0 accept 
                oifname "docker0" counter packets 0 bytes 0 jump DOCKER 
                iifname "docker0" oifname != "docker0" counter packets 0 bytes 0 accept 
                iifname "docker0" oifname "docker0" counter packets 0 bytes 0 accept 
                oifname "br-8bad6f7ab7c0" ct state related,established counter packets 0 bytes 0 accept 
                oifname "br-8bad6f7ab7c0" counter packets 0 bytes 0 jump DOCKER 
                iifname "br-8bad6f7ab7c0" oifname != "br-8bad6f7ab7c0" counter packets 0 bytes 0 accept 
                iifname "br-8bad6f7ab7c0" oifname "br-8bad6f7ab7c0" counter packets 0 bytes 0 accept 
        } 

        chain DOCKER-USER { 
                counter packets 0 bytes 0 return 
        } 
} 
table ip6 nat { 
        chain DOCKER { 
        } 
} 
table ip6 filter { 
        chain DOCKER { 
        } 

        chain DOCKER-ISOLATION-STAGE-1 { 
                iifname "docker0" oifname != "docker0" counter packets 0 bytes 0 jump DOCKER-ISOLATION-STAGE-2 
                iifname "br-8bad6f7ab7c0" oifname != "br-8bad6f7ab7c0" counter packets 0 bytes 0 jump DOCKER-ISOLATION-STAGE-2 
                counter packets 0 bytes 0 return 
        } 

        chain DOCKER-ISOLATION-STAGE-2 { 
                oifname "docker0" counter packets 0 bytes 0 drop 
                oifname "br-8bad6f7ab7c0" counter packets 0 bytes 0 drop 
                counter packets 0 bytes 0 return 
        } 

        chain FORWARD { 
                type filter hook forward priority filter; policy drop; 
                counter packets 0 bytes 0 jump DOCKER-USER 
        } 

        chain DOCKER-USER { 
                counter packets 0 bytes 0 return 
        } 
}
EOF

# 应用Docker规则
nft -f /tmp/docker_rules.nft

# 清理临时文件
rm -f /tmp/docker_rules.nft

echo "sing-box 服务已停止,防火墙规则已清理并重新应用了Docker规则."
