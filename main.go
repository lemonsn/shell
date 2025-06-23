package main

import ( "github.com/caddyserver/caddy/caddy/caddymain"

        // plug in plugins here
        // for example:
        _ "github.com/caddyserver/dnsproviders/alidns"
        _ "github.com/caddyserver/dnsproviders/cloudflare"
        _ "github.com/caddyserver/dnsproviders/dnspod"
        _ "github.com/hacdias/caddy-webdav"
        _ "github.com/caddyserver/forwardproxy"
        _ "github.com/nicolasazrak/caddy-cache"
        _ "github.com/pyed/ipfilter"
        _ "github.com/Xumeiquer/nobots"
        _ "github.com/xuqingfeng/caddy-rate-limit"
        _ "github.com/captncraig/caddy-realip"
)

func main() {
        // optional: disable
        // telemetry
        caddymain.EnableTelemetry = false
        caddymain.Run()
}
