#!/usr/bin/env bash
# install.sh — ask 자동 설치 스크립트 (Ubuntu/Debian, Linux 전용)
#
# 하는 일:
#   1. 의존성 체크 (jq, curl, python3-rich, 선택: glow, huggingface-cli)
#   2. llama.cpp 빌드 결과물 위치 확인
#   3. 모델 디렉토리 설정
#   4. systemd 서비스 파일 생성 (~/.config/systemd/user/llama-server.service)
#   5. 첫 모델 다운로드 메뉴 (선택)
#   6. 서비스 시작 + 작동 검증
#   7. PATH 등록 안내
#
# 미리 해두어야 할 것:
#   - llama.cpp 빌드 (사용자 GPU에 맞춰 직접). 빌드 가이드: https://github.com/ggml-org/llama.cpp

set -uo pipefail

# ============================================================
# 출력 헬퍼
# ============================================================
C_OK=$'\e[32m'
C_FAIL=$'\e[31m'
C_WARN=$'\e[33m'
C_INFO=$'\e[36m'
C_BOLD=$'\e[1m'
C_RESET=$'\e[0m'

ok()    { echo "${C_OK}[OK]${C_RESET} $*"; }
fail()  { echo "${C_FAIL}[FAIL]${C_RESET} $*" >&2; }
warn()  { echo "${C_WARN}[WARNING]${C_RESET} $*"; }
info()  { echo "${C_INFO}[INFO]${C_RESET} $*"; }
step()  { echo; echo "${C_BOLD}[$1/$2] $3${C_RESET}"; }
abort() { fail "$*"; echo; fail "설치 중단. 위 메시지 확인 후 다시 실행하세요."; exit 1; }

# 질문 헬퍼: ask_yn "질문" [기본 y|n]
ask_yn() {
  local prompt="$1" default="${2:-y}" reply
  local hint="[Y/n]"; [ "$default" = "n" ] && hint="[y/N]"
  while true; do
    read -rp "  $prompt $hint " reply
    reply="${reply:-$default}"
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) echo "    y 또는 n 으로 답해주세요." ;;
    esac
  done
}

# 질문 헬퍼: ask_value "질문" "기본값"
ask_value() {
  local prompt="$1" default="$2" reply
  read -rp "  $prompt [기본: $default] " reply
  echo "${reply:-$default}"
}

# ============================================================
# 사전 점검
# ============================================================
echo "${C_BOLD}=== ask 자동 설치 스크립트 ===${C_RESET}"
echo "대상: Ubuntu/Debian 계열 Linux"
echo "필요 시간: 약 5분 (모델 다운로드 제외)"
echo

if [ "$EUID" -eq 0 ]; then
  abort "root로 실행하지 마세요. 일반 사용자로 실행하세요 (sudo는 필요 시점에 직접 물어봅니다)."
fi

if ! command -v apt &>/dev/null; then
  warn "이 스크립트는 apt를 사용하는 배포판(Ubuntu/Debian) 전용입니다."
  warn "다른 배포판(Fedora/Arch 등)에서는 의존성 설치를 직접 해야 할 수 있습니다."
  ask_yn "그래도 계속할까요?" n || abort "사용자 중단"
fi

if ! systemctl --user is-active default.target &>/dev/null; then
  if ! command -v systemctl &>/dev/null; then
    abort "systemctl 명령을 찾을 수 없습니다. systemd가 필요합니다."
  fi
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASK_BIN="$REPO_DIR/ask"
[ -x "$ASK_BIN" ] || abort "$ASK_BIN 파일이 없거나 실행 권한이 없습니다. git clone이 정상 완료되었나요?"

# ============================================================
# [1/6] 의존성 체크 + 설치
# ============================================================
step 1 6 "의존성 확인"

declare -A APT_DEPS=(
  [jq]=jq
  [curl]=curl
)
declare -A PIP_DEPS=(
  [rich]=rich
)
declare -A OPT_APT_DEPS=(
)

missing_apt=()
for cmd in "${!APT_DEPS[@]}"; do
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd 설치되어 있음"
  else
    warn "$cmd 없음"
    missing_apt+=("${APT_DEPS[$cmd]}")
  fi
done

# python3 + rich
if ! command -v python3 &>/dev/null; then
  warn "python3 없음 (마크다운 렌더링에 필요)"
  missing_apt+=(python3 python3-pip)
fi

if ! python3 -c 'import rich' &>/dev/null; then
  warn "python3-rich 없음 (마크다운 렌더링에 필요)"
  if dpkg -l python3-rich &>/dev/null; then
    : # 이미 dpkg에는 있지만 import 실패 — 드문 경우, 패스
  else
    missing_apt+=(python3-rich)
  fi
fi

if [ ${#missing_apt[@]} -gt 0 ]; then
  info "설치 필요 패키지: ${missing_apt[*]}"
  if ask_yn "지금 apt로 설치할까요? (sudo 필요)"; then
    sudo apt update && sudo apt install -y "${missing_apt[@]}" || abort "패키지 설치 실패"
    ok "필수 패키지 설치 완료"
  else
    warn "필수 패키지 설치를 건너뜁니다. 일부 기능이 동작하지 않을 수 있습니다."
  fi
else
  ok "모든 필수 패키지 준비 완료"
fi

# 선택 도구
if ! command -v glow &>/dev/null; then
  info "glow 없음 (선택: askmanual 페이저로 사용, rich 실패 시 마크다운 fallback)"
  if ask_yn "glow를 snap으로 설치할까요?" n; then
    sudo snap install glow || warn "glow 설치 실패 — 건너뜁니다"
  fi
fi

if ! command -v huggingface-cli &>/dev/null; then
  info "huggingface-cli 없음 (선택: 'ask -i'로 모델 다운로드할 때 필요)"
  if ask_yn "지금 pip으로 설치할까요?" y; then
    pip install --user 'huggingface_hub[cli]' || warn "huggingface-cli 설치 실패 — 'ask -i' 기능 불가"
  fi
fi

# ============================================================
# [2/6] llama.cpp 위치 확인
# ============================================================
step 2 6 "llama.cpp 빌드 위치 확인"

DEFAULT_LLAMA_BIN="$HOME/src/llama.cpp/build/bin/llama-server"
LLAMA_BIN="$DEFAULT_LLAMA_BIN"

while true; do
  LLAMA_BIN="$(ask_value 'llama-server 바이너리 경로?' "$LLAMA_BIN")"
  LLAMA_BIN="${LLAMA_BIN/#\~/$HOME}"
  if [ -x "$LLAMA_BIN" ]; then
    ok "찾음: $LLAMA_BIN"
    break
  fi
  fail "$LLAMA_BIN 가 없거나 실행 권한이 없습니다."
  info "llama.cpp 빌드 가이드: https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md"
  if ! ask_yn "다른 경로로 다시 시도?" y; then
    abort "llama.cpp가 필요합니다. 빌드 후 다시 실행하세요."
  fi
done

# ============================================================
# [3/6] 모델 디렉토리 설정
# ============================================================
step 3 6 "모델 디렉토리 설정"

DEFAULT_MODEL_DIR="$HOME/models"
MODEL_DIR="$(ask_value '모델 저장 디렉토리?' "$DEFAULT_MODEL_DIR")"
MODEL_DIR="${MODEL_DIR/#\~/$HOME}"
mkdir -p "$MODEL_DIR" || abort "$MODEL_DIR 생성 실패"
ok "모델 디렉토리: $MODEL_DIR"

if [ "$MODEL_DIR" != "$HOME/models" ]; then
  warn "현재 ask 스크립트는 ~/models/ 경로가 코드에 박혀 있습니다."
  warn "다른 경로를 쓰려면 ~/Code/Claude/ask/ask 안의 '~/models' 부분을 직접 치환해야 합니다."
  warn "이번 버전에선 ~/models를 사용합니다."
  MODEL_DIR="$HOME/models"
  mkdir -p "$MODEL_DIR"
fi

# ============================================================
# [4/6] systemd 서비스 파일 생성
# ============================================================
step 4 6 "systemd 사용자 서비스 파일 생성"

SVC_DIR="$HOME/.config/systemd/user"
SVC_FILE="$SVC_DIR/llama-server.service"
mkdir -p "$SVC_DIR"

if [ -f "$SVC_FILE" ]; then
  warn "기존 서비스 파일이 있습니다: $SVC_FILE"
  if ! ask_yn "덮어쓸까요? (백업 자동 생성)" n; then
    info "기존 서비스 파일 유지. [4/6] 건너뜀."
    SVC_SKIP=1
  else
    cp "$SVC_FILE" "$SVC_FILE.bak_$(date +%y%m%d_%H%M%S)"
    ok "백업: $SVC_FILE.bak_*"
  fi
fi

if [ -z "${SVC_SKIP:-}" ]; then
  # 모델 미리 결정: 사용 가능한 모델이 있으면 그것, 없으면 placeholder
  FIRST_GGUF=$(find "$MODEL_DIR" -maxdepth 2 -name '*.gguf' 2>/dev/null | head -1)
  if [ -n "$FIRST_GGUF" ]; then
    MODEL_PATH="$FIRST_GGUF"
    MODEL_ALIAS="$(basename "$(dirname "$FIRST_GGUF")")"
    ok "기존 모델 발견: $MODEL_ALIAS ($MODEL_PATH)"
  else
    MODEL_PATH="$MODEL_DIR/PLACEHOLDER/model.gguf"
    MODEL_ALIAS="PLACEHOLDER"
    info "모델이 아직 없습니다. placeholder로 서비스 파일을 만들고, [5/6]에서 모델 다운로드 후 'ask -l'로 전환하세요."
  fi

  CTX_SIZE="$(ask_value 'context 크기 (토큰 단위)?' 131072)"

  if command -v nvidia-smi &>/dev/null; then
    GPU_LINE='Environment="CUDA_VISIBLE_DEVICES=0"'
    GPU_LAYERS_LINE='  --n-gpu-layers 999 \'
  else
    warn "nvidia-smi 없음 — CPU 모드로 서비스 파일 생성"
    GPU_LINE='# Environment="CUDA_VISIBLE_DEVICES=0"  # NVIDIA GPU 사용 시 주석 해제'
    GPU_LAYERS_LINE='  # --n-gpu-layers 999 \  # NVIDIA GPU 사용 시 주석 해제'
  fi

  cat > "$SVC_FILE" <<EOF
[Unit]
Description=llama.cpp Server (ask 자동 설치)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
$GPU_LINE
ExecStart=$LLAMA_BIN \\
  --model $MODEL_PATH \\
  --alias $MODEL_ALIAS \\
  --host 127.0.0.1 \\
  --port 8080 \\
  --ctx-size $CTX_SIZE \\
$GPU_LAYERS_LINE
  --flash-attn auto \\
  --cache-type-k q8_0 \\
  --cache-type-v q8_0 \\
  --jinja \\
  --reasoning auto \\
  --reasoning-budget 256 \\
  --parallel 1
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
  ok "서비스 파일 생성: $SVC_FILE"
fi

# ============================================================
# [5/6] 첫 모델 다운로드 (선택)
# ============================================================
step 5 6 "첫 모델 다운로드 (선택)"

if [ -n "$FIRST_GGUF" ]; then
  info "이미 모델이 있어 [5/6] 건너뜀."
elif ! command -v huggingface-cli &>/dev/null; then
  warn "huggingface-cli가 없어 자동 다운로드 불가."
  info "수동: '$MODEL_DIR/<모델명>/<파일>.gguf' 위치에 GGUF 파일을 두세요."
else
  echo "  추천 모델 (참고용, 디스크/RAM에 맞춰 선택):"
  echo "    1) Qwen3-4B  Q4_K_M     ~2.5 GB   (가볍고 빠름, 8GB+ RAM)"
  echo "    2) Qwen3-9B  Q4_K_M     ~5.5 GB   (중간 크기, 16GB+ RAM, 6GB+ VRAM 권장)"
  echo "    3) Gemma-2-27B Q4_K_M   ~16 GB    (큼, 32GB+ RAM, 24GB+ VRAM 권장)"
  echo "    n) 건너뛰기 (나중에 'ask -i <repo>' 로 받기)"
  read -rp "  선택 [1/2/3/n]: " choice
  case "${choice:-n}" in
    1) REPO="Qwen/Qwen3-4B-GGUF"; QUANT="Q4_K_M" ;;
    2) REPO="Qwen/Qwen3-9B-GGUF"; QUANT="Q4_K_M" ;;
    3) REPO="bartowski/gemma-2-27b-it-GGUF"; QUANT="Q4_K_M" ;;
    *) REPO=""; info "모델 다운로드 건너뜀" ;;
  esac
  if [ -n "$REPO" ]; then
    info "다운로드: $REPO ($QUANT)"
    "$ASK_BIN" -i "$REPO" "$QUANT" || warn "다운로드 실패 — 직접 'ask -i' 재시도하세요"
  fi
fi

# ============================================================
# [6/6] 서비스 시작 + 작동 확인
# ============================================================
step 6 6 "서비스 시작 + 작동 확인"

systemctl --user daemon-reload || abort "systemctl daemon-reload 실패"
ok "systemd 설정 다시 읽음"

# placeholder 상태면 시작 시도해도 실패하므로 안내만
if grep -q "PLACEHOLDER" "$SVC_FILE"; then
  warn "서비스 파일에 PLACEHOLDER가 남아있어 자동 시작을 건너뜁니다."
  info "모델 다운로드 후: 'ask -l' 로 모델 선택 → 자동 서비스 재시작"
else
  systemctl --user enable llama-server.service &>/dev/null || warn "enable 실패 (재부팅 시 자동 시작 안 됨)"
  if systemctl --user restart llama-server.service; then
    ok "llama-server 서비스 재시작 명령 보냄"
    info "초기화 대기 중... (최대 30초)"
    for i in $(seq 1 30); do
      if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health 2>/dev/null | grep -q 200; then
        ok "서버 응답 확인 (http://127.0.0.1:8080)"
        break
      fi
      sleep 1
      [ "$i" -eq 30 ] && warn "30초 내 응답 없음. 'systemctl --user status llama-server.service' 확인"
    done
  else
    warn "서비스 시작 실패. 'journalctl --user -u llama-server.service -n 30' 로 로그 확인"
  fi
fi

# ============================================================
# 마무리: PATH 등록 안내
# ============================================================
echo
echo "${C_BOLD}=== 설치 마무리 ===${C_RESET}"

if echo "$PATH" | tr ':' '\n' | grep -qx "$REPO_DIR"; then
  ok "PATH에 $REPO_DIR 이미 등록됨"
else
  warn "PATH에 $REPO_DIR 가 없습니다."
  info "다음 한 줄을 ~/.bashrc 끝에 추가하세요:"
  echo
  echo "    export PATH=\"$REPO_DIR:\$PATH\""
  echo
  if ask_yn "지금 ~/.bashrc에 자동 추가할까요?" y; then
    {
      echo ""
      echo "# ask 자동 설치 (install.sh가 추가) — $(date +%F)"
      echo "export PATH=\"$REPO_DIR:\$PATH\""
    } >> ~/.bashrc
    ok "~/.bashrc에 추가 완료. 새 터미널 열거나 'source ~/.bashrc' 실행."
  fi
fi

echo
ok "설치 완료. 새 터미널에서 다음을 시도하세요:"
echo
echo "    ask --help"
echo "    ask -l            # 설치된 모델 목록 + 전환"
echo "    ask \"안녕\""
echo
info "자세한 사용법: $REPO_DIR/manual.md  또는  'askmanual' (glow 설치 시)"
