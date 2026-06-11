#!/usr/bin/env bash
set -Eeuo pipefail

# End-to-end smoke test for HTTP-FLV, HTTP-TS and HTTP-PS publishing.
#
# Usage:
#   tests/http_publish_smoke.sh [/path/to/MediaServer]
#
# Environment:
#   MEDIA_SERVER_BIN  MediaServer binary path. Overrides the positional arg.
#   HTTP_PORT         Local HTTP port to bind. Defaults to a free loopback port.
#   KEEP_TMP=1        Keep generated config, logs and media captures after success.
#   EXPECT_TS_DISABLED=1  Expect HTTP-TS publish setup to return 503.
#   EXPECT_PS_DISABLED=1  Expect HTTP-PS publish setup to return 503.
#   HOOK_PORT         Local webhook port to bind. Defaults to a free loopback port.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

case "$(uname -s)" in
  Darwin) OS_DIR="darwin" ;;
  Linux) OS_DIR="linux" ;;
  *) OS_DIR="$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
esac

DEFAULT_MEDIA_SERVER_BIN="${ROOT_DIR}/release/${OS_DIR}/Debug/MediaServer"
MEDIA_SERVER_BIN="${MEDIA_SERVER_BIN:-${1:-${DEFAULT_MEDIA_SERVER_BIN}}}"

gha_escape() {
  local msg="$*"
  msg="${msg//'%'/'%25'}"
  msg="${msg//$'\r'/'%0D'}"
  msg="${msg//$'\n'/'%0A'}"
  printf '%s' "${msg}"
}

gha_error() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::error::%s\n' "$(gha_escape "$*")" >&2
  fi
}

die() {
  echo "ERROR: $*" >&2
  gha_error "$*"
  exit 1
}

log() {
  printf '[http-publish-smoke] %s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

alloc_port() {
  python3 - <<'PY'
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

need_cmd python3
need_cmd curl

EXPECT_TS_DISABLED="${EXPECT_TS_DISABLED:-0}"
EXPECT_PS_DISABLED="${EXPECT_PS_DISABLED:-0}"
if [[ "${EXPECT_TS_DISABLED}" != "1" && "${EXPECT_PS_DISABLED}" != "1" ]]; then
  need_cmd ffmpeg
fi

[[ -x "${MEDIA_SERVER_BIN}" ]] || die "MediaServer is not executable: ${MEDIA_SERVER_BIN}"

HTTP_PORT="${HTTP_PORT:-$(alloc_port)}"
HOOK_PORT="${HOOK_PORT:-$(alloc_port)}"
SECRET="http-publish-smoke-$RANDOM-$RANDOM"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zlm-http-publish-smoke.XXXXXX")"
CONFIG_FILE="${TMP_DIR}/config.ini"
LOG_DIR="${TMP_DIR}/log"
SERVER_STDOUT="${TMP_DIR}/mediaserver.stdout.log"
HOOK_STDOUT="${TMP_DIR}/hook.stdout.log"
mkdir -p "${LOG_DIR}"

SERVER_PID=""
HOOK_PID=""
PUSH_PIDS=()
LAST_PUSH_PID=""

cleanup() {
  local status=$?

  for pid in "${PUSH_PIDS[@]:-}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done

  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${HOOK_PID}" ]] && kill -0 "${HOOK_PID}" >/dev/null 2>&1; then
    kill "${HOOK_PID}" >/dev/null 2>&1 || true
    wait "${HOOK_PID}" >/dev/null 2>&1 || true
  fi

  if [[ "${status}" -ne 0 ]]; then
    gha_error "HTTP publish smoke failed with exit status ${status}; see smoke diagnostics below"
    for file in "${SERVER_STDOUT}" "${HOOK_STDOUT}" "${TMP_DIR}"/*.log; do
      [[ -f "${file}" ]] || continue
      echo "---- ${file} ----" >&2
      tail -n 120 "${file}" >&2 || true
    done
  fi

  if [[ "${status}" -eq 0 && "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "${TMP_DIR}"
  else
    echo "Artifacts kept at: ${TMP_DIR}" >&2
    [[ -f "${SERVER_STDOUT}" ]] && echo "MediaServer stdout: ${SERVER_STDOUT}" >&2
    [[ -f "${HOOK_STDOUT}" ]] && echo "Webhook stdout: ${HOOK_STDOUT}" >&2
  fi

  exit "${status}"
}
trap cleanup EXIT

python3 - "${ROOT_DIR}/conf/config.ini" "${CONFIG_FILE}" "${SECRET}" "${HTTP_PORT}" "${HOOK_PORT}" <<'PY'
import re
import sys

src, dst, secret, http_port, hook_port = sys.argv[1:6]

updates = {
    ("api", "secret"): secret,
    ("general", "listen_ip"): "127.0.0.1",
    ("protocol", "enable_audio"): "1",
    ("protocol", "add_mute_audio"): "1",
    ("protocol", "auto_close"): "0",
    ("protocol", "continue_push_ms"): "0",
    ("protocol", "enable_hls"): "0",
    ("protocol", "enable_hls_fmp4"): "0",
    ("protocol", "enable_mp4"): "0",
    ("protocol", "enable_rtsp"): "0",
    ("protocol", "enable_rtmp"): "1",
    ("protocol", "enable_ts"): "1",
    ("protocol", "enable_fmp4"): "0",
    ("http", "port"): http_port,
    ("http", "sslport"): "0",
    ("http", "keepAliveSecond"): "15",
    ("hook", "enable"): "1",
    ("hook", "on_publish"): f"http://127.0.0.1:{hook_port}/on_publish",
    ("hook", "timeoutSec"): "5",
    ("hook", "retry"): "0",
    ("rtmp", "port"): "0",
    ("rtmp", "sslport"): "0",
    ("rtp_proxy", "port"): "0",
    ("rtc", "signalingPort"): "0",
    ("rtc", "signalingSslPort"): "0",
    ("rtc", "icePort"): "0",
    ("rtc", "iceTcpPort"): "0",
    ("rtc", "port"): "0",
    ("rtc", "tcpPort"): "0",
    ("srt", "port"): "0",
    ("rtsp", "port"): "0",
    ("rtsp", "sslport"): "0",
    ("shell", "port"): "0",
    ("onvif", "port"): "0",
}

section = None
seen = set()
out = []

with open(src, "r", encoding="utf-8-sig") as f:
    for line in f:
        match = re.match(r"\s*\[([^]]+)]\s*$", line)
        if match:
            section = match.group(1)
            out.append(line)
            continue

        if section:
            key_match = re.match(r"(\s*)([^#;\s][^=\s]*)(\s*)=.*$", line)
            if key_match:
                key = key_match.group(2)
                update_key = (section, key)
                if update_key in updates:
                    out.append(f"{key}={updates[update_key]}\n")
                    seen.add(update_key)
                    continue

        out.append(line)

missing_by_section = {}
for update_key, value in updates.items():
    if update_key not in seen:
        missing_by_section.setdefault(update_key[0], []).append((update_key[1], value))

if missing_by_section:
    out.append("\n# Added by tests/http_publish_smoke.sh\n")
    for sec, items in missing_by_section.items():
        out.append(f"[{sec}]\n")
        for key, value in items:
            out.append(f"{key}={value}\n")

with open(dst, "w", encoding="utf-8") as f:
    f.writelines(out)
PY

BASE_URL="http://127.0.0.1:${HTTP_PORT}"
HOOK_URL="http://127.0.0.1:${HOOK_PORT}"

start_hook_server() {
  local hook_script="${TMP_DIR}/hook_server.py"

  cat >"${hook_script}" <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        sys.stderr.write((fmt % args) + "\n")

    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"ok": True})
            return
        self._send_json(404, {"code": 404})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length)
        body = {}
        if raw:
            body = json.loads(raw.decode("utf-8"))

        response = {"code": 0}
        stream = str(body.get("stream", ""))
        if stream.startswith("replace_origin_"):
            response["stream_replace"] = "smoke_replace_shared"
        self._send_json(200, response)


server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
server.serve_forever()
PY

  log "starting webhook server on ${HOOK_URL}"
  python3 "${hook_script}" "${HOOK_PORT}" >"${HOOK_STDOUT}" 2>&1 &
  HOOK_PID=$!

  local deadline=$((SECONDS + 10))
  while (( SECONDS < deadline )); do
    if ! kill -0 "${HOOK_PID}" >/dev/null 2>&1; then
      tail -n 80 "${HOOK_STDOUT}" >&2 || true
      die "webhook server exited during startup"
    fi

    local code
    code="$(curl -sS --max-time 1 -o /dev/null -w '%{http_code}' "${HOOK_URL}/health" 2>/dev/null || true)"
    if [[ "${code}" == "200" ]]; then
      log "webhook server is accepting HTTP connections"
      return 0
    fi
    sleep 0.25
  done

  tail -n 80 "${HOOK_STDOUT}" >&2 || true
  die "webhook server did not start within 10 seconds"
}

start_server() {
  log "starting MediaServer on ${BASE_URL}"
  (
    cd "$(dirname "${MEDIA_SERVER_BIN}")"
    "${MEDIA_SERVER_BIN}" -c "${CONFIG_FILE}" -l 2 -t 2 --log-dir "${LOG_DIR}" --log-slice 2 --log-size 16
  ) >"${SERVER_STDOUT}" 2>&1 &
  SERVER_PID=$!

  local deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      tail -n 80 "${SERVER_STDOUT}" >&2 || true
      die "MediaServer exited during startup"
    fi

    local code
    code="$(curl -sS --max-time 1 -o /dev/null -w '%{http_code}' "${BASE_URL}/" 2>/dev/null || true)"
    if [[ "${code}" != "000" ]]; then
      log "MediaServer is accepting HTTP connections"
      return 0
    fi
    sleep 0.25
  done

  tail -n 80 "${SERVER_STDOUT}" >&2 || true
  die "MediaServer did not start within 15 seconds"
}

start_flv_push() {
  local stream="$1"
  local method="${2:-POST}"
  local suffix="${3:-live.flv}"
  local duration="${4:-7}"
  local url="${BASE_URL}/live/${stream}.${suffix}"
  local log_file="${TMP_DIR}/${stream}.push.${method}.${suffix}.log"

  ffmpeg -hide_banner -loglevel warning -y \
    -re -f lavfi -i "testsrc2=size=320x240:rate=25" \
    -re -f lavfi -i "sine=frequency=1000:sample_rate=44100" \
    -t "${duration}" \
    -c:v libx264 -preset ultrafast -tune zerolatency -g 25 -pix_fmt yuv420p \
    -c:a aac -ar 44100 -b:a 64k \
    -f flv -method "${method}" "${url}" >"${log_file}" 2>&1 &
  LAST_PUSH_PID="$!"
  PUSH_PIDS+=("${LAST_PUSH_PID}")
}

start_ts_push() {
  local stream="$1"
  local method="${2:-POST}"
  local suffix="${3:-live.ts}"
  local duration="${4:-7}"
  local url="${BASE_URL}/live/${stream}.${suffix}"
  local log_file="${TMP_DIR}/${stream}.push.${method}.${suffix}.log"

  ffmpeg -hide_banner -loglevel warning -y \
    -re -f lavfi -i "testsrc2=size=320x240:rate=25" \
    -re -f lavfi -i "sine=frequency=1200:sample_rate=44100" \
    -t "${duration}" \
    -c:v libx264 -preset ultrafast -tune zerolatency -g 25 -pix_fmt yuv420p \
    -c:a aac -ar 44100 -b:a 64k \
    -f mpegts -method "${method}" "${url}" >"${log_file}" 2>&1 &
  LAST_PUSH_PID="$!"
  PUSH_PIDS+=("${LAST_PUSH_PID}")
}

start_ps_push() {
  local stream="$1"
  local method="${2:-POST}"
  local suffix="${3:-live.ps}"
  local duration="${4:-7}"
  local url="${BASE_URL}/live/${stream}.${suffix}"
  local log_file="${TMP_DIR}/${stream}.push.${method}.${suffix}.log"

  ffmpeg -hide_banner -loglevel warning -y \
    -re -f lavfi -i "testsrc2=size=320x240:rate=25" \
    -re -f lavfi -i "sine=frequency=1400:sample_rate=44100" \
    -t "${duration}" \
    -c:v libx264 -preset ultrafast -tune zerolatency -g 25 -pix_fmt yuv420p \
    -c:a mp2 -ar 44100 -b:a 64k \
    -f mpeg -method "${method}" "${url}" >"${log_file}" 2>&1 &
  LAST_PUSH_PID="$!"
  PUSH_PIDS+=("${LAST_PUSH_PID}")
}

decode_flv_playback() {
  local stream="$1"
  local log_file="${TMP_DIR}/${stream}.pull.flv.log"

  ffmpeg -hide_banner -loglevel warning \
    -rw_timeout 5000000 \
    -t 3 -i "${BASE_URL}/live/${stream}.live.flv" \
    -f null - >"${log_file}" 2>&1
}

capture_and_decode_ts_playback() {
  local stream="$1"
  local capture_file="${TMP_DIR}/${stream}.play.ts"
  local capture_log="${TMP_DIR}/${stream}.pull.ts.log"
  local decode_log="${TMP_DIR}/${stream}.decode.ts.log"

  ffmpeg -hide_banner -loglevel warning -y \
    -rw_timeout 5000000 \
    -t 4 -i "${BASE_URL}/live/${stream}.live.ts" \
    -c copy -f mpegts "${capture_file}" >"${capture_log}" 2>&1

  [[ -s "${capture_file}" ]] || die "captured empty HTTP-TS playback for ${stream}"

  ffmpeg -hide_banner -loglevel warning \
    -i "${capture_file}" -t 2 -f null - >"${decode_log}" 2>&1
}

generate_ts_seed() {
  local output_file="$1"

  ffmpeg -hide_banner -loglevel warning -y \
    -f lavfi -i "testsrc2=size=320x240:rate=25" \
    -t 1 \
    -an \
    -c:v libx264 -preset ultrafast -tune zerolatency -g 25 -pix_fmt yuv420p \
    -f mpegts "${output_file}" >"${TMP_DIR}/stream-replace-seed.log" 2>&1

  [[ -s "${output_file}" ]] || die "failed to generate stream_replace TS seed"
}

wait_push() {
  local pid="$1"
  local label="$2"
  if ! wait "${pid}"; then
    die "${label} push process failed; inspect ${TMP_DIR}/${label}.push.*.log"
  fi
}

run_publish_case() {
  local label="$1"
  local stream="$2"
  local start_func="$3"
  shift 3

  log "testing ${label} publish as stream ${stream}"
  local pid
  "${start_func}" "${stream}" "$@"
  pid="${LAST_PUSH_PID}"
  sleep 1.5
  decode_flv_playback "${stream}"
  wait_push "${pid}" "${stream}"
}

test_put_alias_publish() {
  run_publish_case "HTTP-FLV PUT .flv" "smoke_flv_put_alias" start_flv_push PUT flv 5
  run_publish_case "HTTP-TS PUT .ts" "smoke_ts_put_alias" start_ts_push PUT ts 5
  run_publish_case "HTTP-PS PUT .ps" "smoke_ps_put_alias" start_ps_push PUT ps 5
}

test_empty_body_rejection() {
  local out_file="${TMP_DIR}/empty-body.out"
  local code

  code="$(curl -sS --max-time 5 -o "${out_file}" -w '%{http_code}' \
    -X POST -H 'Content-Length: 0' "${BASE_URL}/live/empty_body.live.ts" || true)"

  [[ "${code}" == "400" ]] || die "expected empty HTTP-TS publish body to return 400, got ${code}"
  grep -q "body is empty" "${out_file}" || die "empty-body response did not mention body is empty"
}

expect_disabled_publish() {
  local label="$1"
  local stream="$2"
  local suffix="$3"
  local out_file="${TMP_DIR}/${stream}.disabled.out"
  local code

  log "testing ${label} disabled publish rejection"
  code="$(curl -sS --max-time 5 -o "${out_file}" -w '%{http_code}' \
    -X POST --data-binary 'not-a-real-stream' "${BASE_URL}/live/${stream}.${suffix}" || true)"

  [[ "${code}" == "503" ]] || die "expected ${label} disabled publish to return 503, got ${code}"
  grep -Eq "unavailable|disabled|setup failed" "${out_file}" || \
    die "${label} disabled response did not explain unavailable capability"
}

test_stream_replace_claim() {
  local seed_file="${TMP_DIR}/stream_replace_seed.ts"
  local ready_file="${TMP_DIR}/stream_replace_holder.ready"
  local holder_log="${TMP_DIR}/stream_replace_holder.log"
  local second_out="${TMP_DIR}/stream_replace_second.out"
  local second_code
  local holder_pid

  log "testing on_publish stream_replace claim conflict"
  generate_ts_seed "${seed_file}"

  python3 - "${HTTP_PORT}" "${seed_file}" "${ready_file}" "${holder_log}" <<'PY' &
import socket
import sys
import time

port = int(sys.argv[1])
seed_path, ready_path, log_path = sys.argv[2:5]
path = "/live/replace_origin_a.live.ts"

with open(seed_path, "rb") as f:
    payload = f.read()

with open(log_path, "w", encoding="utf-8") as log:
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    sock.settimeout(5)
    headers = (
        f"POST {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "User-Agent: zlm-http-publish-smoke\r\n"
        "Transfer-Encoding: chunked\r\n"
        "Content-Type: video/mp2t\r\n"
        "\r\n"
    ).encode("ascii")
    chunk = f"{len(payload):X}\r\n".encode("ascii") + payload + b"\r\n"
    sock.sendall(headers + chunk)

    response = b""
    while b"\r\n\r\n" not in response:
        part = sock.recv(4096)
        if not part:
            raise RuntimeError("holder connection closed before response")
        response += part
    log.write(response.decode("iso-8859-1", "replace"))
    log.flush()
    if b" 200 " not in response.split(b"\r\n", 1)[0]:
        raise RuntimeError("holder did not receive 200 OK")

    with open(ready_path, "w", encoding="utf-8") as ready:
        ready.write("ready\n")

    time.sleep(8)
    try:
        sock.sendall(b"0\r\n\r\n")
    except OSError:
        pass
    sock.close()
PY
  holder_pid=$!
  PUSH_PIDS+=("${holder_pid}")

  local deadline=$((SECONDS + 8))
  while (( SECONDS < deadline )); do
    if [[ -f "${ready_file}" ]]; then
      break
    fi
    if ! kill -0 "${holder_pid}" >/dev/null 2>&1; then
      cat "${holder_log}" >&2 || true
      wait "${holder_pid}" || true
      die "stream_replace holder exited before becoming ready"
    fi
    sleep 0.25
  done

  [[ -f "${ready_file}" ]] || die "stream_replace holder did not become ready"

  second_code="$(curl -sS --max-time 5 -o "${second_out}" -w '%{http_code}' \
    -X POST --data-binary @"${seed_file}" "${BASE_URL}/live/replace_origin_b.live.ts" || true)"

  [[ "${second_code}" == "409" ]] || die "expected stream_replace conflict to return 409, got ${second_code}"
  grep -q "Already publishing" "${second_out}" || die "stream_replace conflict response did not mention publishing conflict"

  wait "${holder_pid}" || die "stream_replace holder failed; inspect ${holder_log}"
}

start_hook_server
start_server
test_empty_body_rejection

if [[ "${EXPECT_TS_DISABLED}" == "1" || "${EXPECT_PS_DISABLED}" == "1" ]]; then
  [[ "${EXPECT_TS_DISABLED}" == "1" ]] && expect_disabled_publish "HTTP-TS" "smoke_disabled_ts" "live.ts"
  [[ "${EXPECT_PS_DISABLED}" == "1" ]] && expect_disabled_publish "HTTP-PS" "smoke_disabled_ps" "live.ps"
  log "all requested disabled HTTP publish checks passed"
  exit 0
fi

run_publish_case "HTTP-FLV" "smoke_flv" start_flv_push
run_publish_case "HTTP-TS" "smoke_ts" start_ts_push

log "testing HTTP-TS playback output for HTTP-TS publish"
start_ts_push "smoke_ts_direct"
ts_pid="${LAST_PUSH_PID}"
sleep 1.5
capture_and_decode_ts_playback "smoke_ts_direct"
wait_push "${ts_pid}" "smoke_ts_direct"

test_stream_replace_claim
test_put_alias_publish
run_publish_case "HTTP-PS" "smoke_ps" start_ps_push

log "all HTTP publish smoke checks passed"
