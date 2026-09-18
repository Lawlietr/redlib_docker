// Reverse proxy: http://codeberg.org (127.0.0.1:80) -> https://codeberg.org
// Workaround: the docker daemon (Go 1.26) connection to codeberg.org is
// dropped mid-response by the edge ("unexpected EOF"), while a plain Go
// client works. The daemon probes https then http; /etc/hosts maps
// codeberg.org to 127.0.0.1 so the http fallback lands here, and the
// bearer-token realm is rewritten from https to http so it stays here.
package main

import (
	"context"
	"crypto/tls"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"
)

const upstreamIP = "217.197.84.140"

func main() {
	up, _ := url.Parse("https://codeberg.org")
	dialer := &net.Dialer{Timeout: 30 * time.Second}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialer.DialContext(ctx, network, upstreamIP+":443")
		},
		TLSClientConfig:     &tls.Config{ServerName: "codeberg.org", MinVersion: tls.VersionTLS12},
		MaxIdleConns:        100,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 30 * time.Second,
	}
	proxy := &httputil.ReverseProxy{
		ModifyResponse: func(resp *http.Response) error {
			// Keep the bearer-token realm inside this proxy (http, port 80).
			if wa := resp.Header.Get("WWW-Authenticate"); wa != "" {
				resp.Header.Set("WWW-Authenticate", strings.ReplaceAll(wa, "https://codeberg.org", "http://codeberg.org"))
			}
			return nil
		},
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(up)
			r.Out.Host = "codeberg.org"
		},
		Transport:     transport,
		FlushInterval: -1,
		ErrorHandler: func(w http.ResponseWriter, req *http.Request, err error) {
			log.Printf("proxy error for %s: %v", req.URL, err)
			http.Error(w, "bad gateway", http.StatusBadGateway)
		},
	}
	log.Printf("listening on 127.0.0.1:80 -> %s", up)
	log.Fatal(http.ListenAndServe("127.0.0.1:80", proxy))
}
