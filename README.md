隧道
```
wget file.yunzhuan.qzz.io/file/tunnel && chmod +x tunnel && ./tunnel
```

64m机器专用
```
wget file.yunzhuan.qzz.io/file/64m && chmod +x 64m && ./64m
```

64m_arm机器专用
```
wget file.yunzhuan.qzz.io/file/64m_arm -O 64m && chmod +x 64m && ./64m
```

warp
```
echo -e "nameserver 1.1.1.1\nnameserver 2606:4700:4700::1111" > /etc/resolv.conf
wget file.yunzhuan.qzz.io/file/warp && chmod +x warp && ./warp
```
