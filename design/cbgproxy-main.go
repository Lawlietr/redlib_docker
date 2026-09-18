// Reverse proxy: http://codeberg.org (127.0.0.1:80) -> https://codeberg.org
//
// Workaround for the docker daemon (Go) on this host:
//  - The daemon is dropped by codeberg edge when talking https directly
//    (TLS session cut mid-response, "unexpected EOF"); a plain Go client
//    and curl both work, so traffic is routed through this proxy via the
//    daemonhttps->http fallback + /etc/hosts (codeberg.org -> 127.0.0.1).
//  - The edge also cancels /v2/token requests that carry Basic auth when
//    they come from a Go TLS fingerprint (h2: stream CANCEL, h1: EOF),
//    while the same request via curl is fine. So /v2/token requests are
//    served through a curl subprocess; everything else (Bearer pings,
//    blob uploads/downloads) goes through the Go reverse proxy.
package main

import (
	"os"
	"context"
	"crypto/tls"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const (
	upstreamIP = "217.197.84.140"
	upstream   = "https://codeberg.org"
)

// serveTokenViaCurl re-issues /v2/token against the real upstream using
// curl, because Go-fingerprinted Basic-auth requests get cancelled by the
// edge while curl-fingerprinted ones pass.
func serveTokenViaCurl(w http.ResponseWriter, r *http.Request) {
	bodyFile := "/tmp/cbgproxy_token_body"
	os.Remove(bodyFile)
	args := []string{"-sS", "--max-time", "60",
		"--resolve", "codeberg.org:443:" + upstreamIP,
		"-o", bodyFile, "-w", "%{http_code}"}
	if auth := r.Header.Get("Authorization"); auth != "" {
		args = append(args, "-H", "Authorization: "+auth)
	}
	args = append(args, "-H", "User-Agent: docker/29.8.1 (cbgproxy)")
	args = append(args, upstream+r.URL.RequestURI())

	log.Printf("token via curl: %s auth=%v", r.URL.RequestURI(), r.Header.Get("Authorization") != "")
	var codeOut []byte
	var err error
	for attempt := 1; attempt <= 5; attempt++ {
		codeOut, err = exec.Command("curl", args...).Output()
		if err == nil {
			break
		}
		if ee, ok := err.(*exec.ExitError); ok {
			log.Printf("token curl attempt %d failed: %v stderr=%s", attempt, err, ee.Stderr)
		} else {
			log.Printf("token curl attempt %d failed: %v", attempt, err)
		}
		time.Sleep(time.Duration(attempt*500) * time.Millisecond)
	}
	if err != nil {
		http.Error(w, "token exchange failed", http.StatusBadGateway)
		return
	}
	code, cerr := strconv.Atoi(strings.TrimSpace(string(codeOut)))
	if cerr != nil || code == 0 {
		code = http.StatusBadGateway
	}
	body, rerr := os.ReadFile(bodyFile)
	os.Remove(bodyFile)
	if rerr != nil {
		body = []byte("{}")
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write(body)
}

func main() {
	up, _ := url.Parse(upstream)
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
	mw := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/v2/token") {
			serveTokenViaCurl(w, r)
			return
		}
		proxy.ServeHTTP(w, r)
	})
	log.Printf("listening on 127.0.0.1:80 -> %s", upstream)
	log.Fatal(http.ListenAndServe("127.0.0.1:80", mw))
}
