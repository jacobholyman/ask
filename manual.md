# 🚀 llama.cpp + 멀티 모델 사용 가이드

작성일: 2026-05-12 (업데이트)
환경: Ubuntu, RTX 5090 (32GB VRAM), CUDA 13.1

---

## 📦 설치된 구성

| 컴포넌트 | 위치 | 용도 |
|---|---|---|
| llama.cpp 빌드 | `~/src/llama.cpp/build/bin/` | CUDA sm_120, Flash Attention |
| 모델 디렉토리 | `~/models/<model-name>/` | 여러 GGUF 모델 |
| systemd 서비스 | `~/.config/systemd/user/llama-server.service` | 자동 시작 |
| `ask` 실행 스크립트 | `~/Code/Claude/ask/ask` (PATH 등록) | 터미널 호출 + 모델 관리 |
| `askmanual` alias | `~/.bashrc` | 이 문서 페이저 보기 (glow 필요) |
| HTTP 엔드포인트 | `http://127.0.0.1:8080` | OpenAI 호환 API |

## 🤖 설치된 모델 (예시)

```
~/models/
├── gemma-4-31b/           18 GB  (현재 활성, 55.9 tok/s)
├── qwen3.6-27b/           16 GB  (~65 tok/s, reasoning 강함)
├── qwen3.5-9b/             5.3 GB (~100~150 tok/s 예상)
└── qwen3.5-4b-draft/       2.6 GB (speculative decoding용)
```

현재 활성 모델은 `ask -L` 또는 `ask -l`로 확인.

---

## 🤖 터미널 사용 (`ask` 함수)

### 📋 모든 flag 요약 (`ask -h`)

```
질문 (대화 히스토리 자동 유지):
  ask "질문"                 이전 대화를 기억하면서 응답 (기본)
  ask -v "질문"              thinking 과정도 표시
  ask -m 4000 "질문"         max_tokens 지정 (기본 2000)
  echo "질문" | ask           파이프만 입력 (질문이 stdin에서 옴)
  cat file | ask "지시"       인자(지시) + 파이프(자료) 결합
                             → "지시\n\n<파일내용>" 으로 전송

대화 히스토리 관리:
  ask -1 "질문"              이번만 단발 (이전 기억 안 읽고, 이번 Q/A도 안 저장)
  ask -r                     히스토리 초기화 (질문 없이)
  ask -r "질문"              초기화 후 새 질문
  ask --history              현재 저장된 대화 보기 (--show 동일)
  ask --limit                현재 한도 보기 (기본: 무제한)
  ask --limit N              수동 설정 (메시지 N개 = N/2 턴)
  ask --limit 0              무제한으로 복귀
  ※ 1턴 = 유저 질문 1개 + 모델 답변 1개 = 2개 메시지
  ※ 기본 무제한 — 매 응답에 ctx 사용량 표시, 'ask -r'로 직접 초기화
  ※ 모델 전환 시 히스토리 자동 초기화 (모델별로 따로 기억 안 함)

출력 형식:
  ask "질문"                 기본: 마크다운 렌더링 (rich, 버퍼 후 출력)
  ask -raw "질문"            raw 스트리밍 (마크다운 변환 없이 그대로)
  (모든 응답 끝에 [TIME] 응답시간/ctx 사용량 표시)

시스템 프롬프트 (모델별 저장):
  ask -S "프롬프트"           현재 활성 모델의 시스템 프롬프트 설정
  ask -S                     현재 모델의 시스템 프롬프트 보기
  ask --sys-clear            현재 모델의 시스템 프롬프트 제거
  ask --sys-list             모든 모델의 시스템 프롬프트 목록

컨텍스트 크기 (모델별 자동 설정):
  ask --show-ctx             현재 모델의 ctx-size (적용/저장/자동)
  ask --set-ctx N            현재 모델의 ctx-size 변경 (재시작 동반)
  ask --list-ctx             모든 모델의 ctx 설정
  ※ 모델 전환 시 자동으로 모델별 ctx 적용 (작은 모델 = 더 큰 ctx)

모델 관리:
  ask -l                     설치된 모델 목록 + 선택 전환
  ask -L                     목록만 출력
  ask -s <키워드>             HuggingFace에서 GGUF repo 검색
  ask -i <repo> [<quant>]    HF에서 모델 다운로드 + 설치
                             기본 quant: Q4_K_M
  ask --rm <model-name>      설치된 모델 삭제
  ask -h                     이 도움말

저장 위치:
  ~/.cache/ask/history.json          현재 모델의 대화 히스토리
  ~/.cache/ask/system_prompts.json   모델별 시스템 프롬프트
  ~/.cache/ask/model_ctx.json        모델별 ctx-size 저장값
  ~/.cache/ask/config.json           --limit 등 전역 설정
```

### 🧠 대화 히스토리 동작

- **위치**: `~/.cache/ask/history.json`
- **유지 한도**: 마지막 20개 메시지 (10턴)
- **자동 초기화 조건**: 다른 모델로 전환 시 (모델 간 컨텍스트 공유 안 됨)
- **수동 초기화**: `ask -r`

**예시 - 멀티턴 대화**:
```bash
$ ask "내 이름은 Jacob이야"
반갑습니다, Jacob님!

$ ask "내 이름 기억해?"
네, Jacob님이라고 하셨죠.

$ ask -r "이제 새 대화"      # 히스토리 리셋
✓ 히스토리 초기화

$ ask --history               # 저장된 대화 보기
[user] 이제 새 대화
[assistant] 네, 새로 시작하시죠!
```

**일회성 질문** (히스토리 안 쓰고 저장도 안 함):
```bash
ask -1 "이 질문은 격리됨"
```

⚠️ 컨텍스트 한도(`--ctx-size 262144` (256K), 약 400,000 한국어 문자 ≒ 책 4권 분량)를 초과하면 모델이 앞부분 잊습니다. 매우 긴 대화 후엔 `ask -r`로 리셋 권장.

> 💡 256K는 학습 시 ctx 한계로, **현재 적용 가능한 최대값**. 모델 전환 시 모델별로 자동 조정됨 (작은 모델도 256K 가능, 22GB+ 큰 모델은 128K).

### 📏 히스토리 한도 (`--limit`, 기본: 무제한)

**기본은 무제한**. 메시지가 ctx 한도까지 누적되고, 사용자가 직접 `ask -r`로 초기화.

매 응답 끝에 ctx 사용량이 표시되므로 직관적으로 관리 가능.

```bash
# 현재 한도 보기
ask --limit
# 현재 히스토리 한도: 무제한 (기본)
#   → ctx-size 한도까지 누적, 매 응답에 ctx 사용량 표시됨
#   → 'ask -r' 로 수동 초기화

# 수동으로 50개 고정 (오래된 자동 삭제)
ask --limit 50

# 무제한으로 복귀
ask --limit 0
```

**예시 워크플로우**:
```bash
ask -r "새 주제 시작"
# [⏱ 1.8s · 12자 · 7자/s · ctx: 100/262,144 (100% free)]

ask "추가 질문"
# [⏱ 2.5s · 25자 · 10자/s · ctx: 250/262,144 (100% free)]

# ... 100턴 후 ...
ask "또 질문"
# [⏱ 4.2s · ... · ctx: 180,000/262,144 (31% free)]   ← 노란색 경고

# ctx 90% 넘으면 빨간색 → 'ask -r'로 초기화
```

⚠️ ctx 사용량은 응답 후 표시되며, 색상:
- **회색**: 70% 미만 (정상)
- **노란색 bold**: 70~90% (주의)
- **빨간색 bold**: 90% 이상 (곧 잘림, 초기화 권장)

### 마크다운 렌더링 (기본 동작)

`ask` 함수가 **기본적으로 마크다운 렌더링**을 수행합니다. 별도 플래그 불필요.

```bash
ask "Python 데코레이터 예제 3개를 표로 정리"   # 기본: 마크다운 렌더링
ask -raw "raw 스트리밍 보고 싶을 때"           # 마크다운 끄기
```

**동작 방식 (기본 마크다운 모드)**:
- 응답을 모두 받은 후 **rich** (Python 라이브러리)로 변환
- 받는 동안 진행 점 (`.`) 표시
- 헤더: `###` 제거, 보라색 bold로 표시
- 코드 블록: 신택스 하이라이트 (배경색 포함)
- 리스트: 글머리 기호로 깔끔하게

**렌더링 결과 예시**:
- `### 제목` -> **제목** (보라색 굵게)
- `- 항목` -> 글머리 기호 항목
- ` ```python\nprint("hi")\n``` ` -> 색상 입혀진 코드 박스

**`ask` (기본) vs `ask -raw` 비교**:
| 명령 | 응답 표시 | 장점 | 단점 |
|---|---|---|---|
| **`ask`** (기본) | 끝에 rich 렌더링 | 깔끔, 코드 하이라이트 | 응답 끝나야 보임 |
| `ask -raw` | raw 스트리밍 | 즉시 피드백, 모델 출력 그대로 | 마크다운 raw (`**`, `#` 그대로 노출) |

**의존성**:
- `rich` (Python, 이미 설치됨)
- `rich` 없을 시 자동으로 `glow`로 fallback (단, glow는 `###` prefix 그대로 노출함)
- 모두 없을 시 raw 텍스트 출력으로 자동 fallback

### ⏱  응답 시간 + ctx 사용량 (자동)

모든 응답 끝에 자동 표시:

```
[⏱  2.3s · 156자 · 68자/s · ctx: 1,234/262,144 (99% free)]
```

- **시간**: 질문 입력 → 응답 완료까지 wall clock
- **글자수**: 응답 본문 길이 (thinking 제외)
- **속도**: 글자/초 (한국어 기준 약 1.5배 곱하면 토큰/초)
- **ctx 사용량**: 전체 컨텍스트 중 누적 사용 / 전체 (남은 % 표시)

**ctx 색상 변화** (시각적 경고):
- ⚪ 회색 (~70% 미만): 정상
- 🟡 노란색 bold (70~90%): 주의
- 🔴 빨간색 bold (90%+): 곧 잘림 → `ask -r` 권장

### 🎭 시스템 프롬프트 (모델별)

각 모델마다 다른 페르소나/지시를 영구 저장. 모델 전환 시 자동으로 해당 모델의 프롬프트 적용.

- **저장 위치**: `~/.cache/ask/system_prompts.json`
- **구조**: `{"모델alias": "프롬프트", ...}`
- **자동 동작**: 시스템 프롬프트 설정/제거 시 대화 히스토리 자동 초기화

**예시 - 모델별 페르소나 설정**:
```bash
# Gemma4-31B에 한국어 코드 리뷰어 페르소나
ask -l   # → gemma-4-31b 선택
ask -S "당신은 친절한 시니어 한국 개발자입니다. 모든 코드 리뷰는 한국어로, 보안 이슈를 우선 점검하세요."

# Qwen3.6-27B는 다른 페르소나
ask -l   # → qwen3.6-27b로 전환
ask -S "당신은 영문 학술 논문을 한국어로 번역하는 전문가입니다."

# 둘 다 보기
ask --sys-list
# === 모델별 시스템 프롬프트 (2개) ===
#
# [▶ qwen3.6-27b]      ← 현재 활성
# 당신은 영문 학술 논문을 한국어로 번역하는 전문가입니다.
#
# [  gemma-4-31b]
# 당신은 친절한 시니어 한국 개발자입니다. ...
```

**현재 모델의 프롬프트 확인**:
```bash
ask -S
# === [gemma-4-31b] 시스템 프롬프트 ===
# 당신은 친절한 시니어 한국 개발자입니다. ...
```

**제거**:
```bash
ask --sys-clear
# ✓ [gemma-4-31b] 시스템 프롬프트 제거
#   → 대화 히스토리 초기화됨
```

**활용 예시**:
- 코드 리뷰 모델: "보안/성능/가독성 순으로 평가"
- 번역 모델: "원문 의미를 살리되 한국어 자연스러움 우선"
- 글쓰기 모델: "친근한 반말로, 이모지는 쓰지 말 것"
- 추론 모델: "단계별로 생각하되 결론은 한 줄로"

### 🗣️ 질문 모드

```bash
# 기본 사용 (현재 활성 모델)
ask "한국 수도는?"

# thinking 과정 같이 보기 (Qwen/Gemma 추론 모델)
ask -v "복잡한 알고리즘 문제"

# 긴 답변
ask -m 4000 "Python 클래스 상세 설명"

# 파일 내용 분석
ask "$(cat code.py) 이 코드 리뷰해줘"

# 파이프 입력
cat error.log | ask "이 에러 원인은?"
echo "안녕" | ask

# 영문도 가능
ask "Write a haiku about AI"
```

### 📚 모델 목록/전환 (`-l` / `-L`)

```bash
# 설치된 모델 목록 + 선택해서 전환 (인터랙티브)
ask -l

# 예시 출력:
# === 설치된 모델 ===
#  [1] ▶ gemma-4-31b               18GB
#  [2]   qwen3.5-4b-draft          2.6GB
#  [3]   qwen3.5-9b                5.3GB
#  [4]   qwen3.6-27b               16GB
#
#  ▶ = 현재 활성
#
# 전환할 번호 (Enter=취소): 4
# → qwen3.6-27b 으로 전환 중...
# 모델 로딩 중... (큰 모델은 30초+)
# ✓ qwen3.6-27b 활성화 완료

# 목록만 보기 (전환 안 함)
ask -L
```

**모델 전환 작동 방식**:
- systemd 서비스 파일의 `--model` 경로와 `--alias` 자동 수정
- 서비스 자동 재시작 + 모델 로딩 대기
- `ask` 함수는 매번 service에서 alias 동적으로 읽음 → 별도 설정 변경 불필요

### 🔍 HuggingFace 검색 (`-s`)

```bash
ask -s "qwen3.5"
# === HuggingFace GGUF repo 검색: 'qwen3.5' ===
#   unsloth/Qwen3.5-9B-GGUF                (DL: 1,139,187)
#   bartowski/Qwen3.5-9B-GGUF              (DL: 524,338)
#   ...

ask -s "gemma-4"
ask -s "llama-4"
ask -s "deepseek"
```

다운로드 수가 많은 게 신뢰도 높음.

### ⬇️ 모델 다운로드/설치 (`-i`)

```bash
# 기본 Q4_K_M
ask -i unsloth/gemma-4-31B-it-GGUF

# 다른 quant 지정
ask -i unsloth/Qwen3.5-9B-GGUF Q5_K_M
ask -i unsloth/Qwen3.5-9B-GGUF Q8_0

# 정확한 파일명 지정 (수동)
ask -i bartowski/some-model-GGUF some-model-Q4_K_M.gguf
```

**동작 흐름**:
1. Repo 존재 확인
2. quant 패턴 매칭으로 파일 찾기 (없으면 가능한 파일 목록 표시)
3. 파일 크기 확인
4. 사용자 확인 (`Y/n`)
5. `~/models/<model-name>/`에 다운로드
6. 완료 후 `ask -l`로 전환

**디렉토리 이름**: repo 마지막 부분에서 `-GGUF` 제거 + 소문자
- `unsloth/Qwen3.5-9B-GGUF` → `~/models/qwen3.5-9b/`

### 🗑️ 모델 삭제 (`--rm`)

```bash
ask --rm qwen3.5-4b-draft
# 삭제 대상: /home/jacob/models/qwen3.5-4b-draft (2.6G)
# 정말 삭제? [y/N]: y
# ✓ 삭제 완료
```

⚠️ 현재 활성 모델은 삭제 불가 (먼저 다른 모델로 전환 필요).

### 📐 추천 quant 선택 가이드

| Quant | 품질 | 속도 | 크기 (예: 30B) | 추천 |
|---|---|---|---|---|
| Q3_K_M | ❌ 손실 큼 | 빠름 | 14GB | 비추 |
| **Q4_K_M** | ⭐ 균형 | 빠름 | 18GB | **기본 추천** |
| Q5_K_M | 좋음 | 보통 | 21GB | 품질 우선 시 |
| Q6_K | 매우 좋음 | 느림 | 25GB | 거의 무손실 |
| Q8_0 | 최상 | 느림 | 32GB | 무손실급 |
| FP16/BF16 | 원본 | 느림 | 60GB | 학습/연구용 |

---

새 터미널부터 자동, 지금 열린 셸에서 즉시 쓰려면: `source ~/.bashrc`

---

## 📖 매뉴얼 보기 (`askmanual`)

이 문서를 페이저 모드로 보려면:

```bash
askmanual
```

내부적으로 `glow -p ~/Code/Claude/ask/manual.md` 실행.

**조작**:
- `j` / `k` 또는 ↑/↓ : 스크롤
- `/검색어` : 검색
- `q` : 종료

⚠️ **glow 설치 필요** (한 번만):
```bash
sudo snap install glow
```

---

## 🌐 웹 UI

```bash
xdg-open http://127.0.0.1:8080
```
브라우저에서 ChatGPT 비슷한 UI로 대화 가능 (대화 히스토리 유지).

---

## 🔌 직접 API 호출 (다른 도구/스크립트 연동)

OpenAI API와 100% 호환되므로 `OPENAI_BASE_URL`을 바꿔주면 어떤 OpenAI 클라이언트라도 연결됩니다.

### Python (openai 라이브러리)
```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:8080/v1", api_key="no-key")
resp = client.chat.completions.create(
    model="qwen3.6-27b",
    messages=[{"role":"user", "content":"질문"}],
)
print(resp.choices[0].message.content)
```

### curl
```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.6-27b",
    "messages": [{"role":"user","content":"질문"}],
    "max_tokens": 2000
  }'
```

### 환경변수만 설정 (대부분의 OpenAI 도구)
```bash
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"
export OPENAI_API_KEY="no-key"
```

---

## ⚙️ 서비스 관리

```bash
# 상태 확인
systemctl --user status llama-server.service

# 재시작
systemctl --user restart llama-server.service

# 일시 정지 (VRAM 회수)
systemctl --user stop llama-server.service

# 다시 시작
systemctl --user start llama-server.service

# 부팅 시 자동 시작 해제
systemctl --user disable llama-server.service

# 자동 시작 재활성
systemctl --user enable llama-server.service

# 실시간 로그
journalctl --user -u llama-server.service -f
```

---

## 🩺 헬스 체크

```bash
# 응답 확인
curl http://127.0.0.1:8080/health
# → {"status":"ok"}

# 로딩된 모델 확인
curl http://127.0.0.1:8080/v1/models | jq

# VRAM 사용량
nvidia-smi --query-gpu=memory.used,memory.free --format=csv

# 포트 확인
ss -tln | grep 8080
```

---

## 🎛️ 현재 설정 요약

| 옵션 | 값 | 의미 |
|---|---|---|
| Context size | **262,144 토큰 (256K, 학습 한계)** | 대화 히스토리 한도 (~400K자, 책 4권) |
| GPU 레이어 | 999 (전부) | 모델 전체 GPU 적재 |
| Flash Attention | auto | Blackwell 가속 |
| KV cache | q8_0 | VRAM 절약 |
| Reasoning | auto / 256 budget | 생각 제한적 사용 |
| Parallel slots | 1 | 동시 요청 1개 |
| VRAM 사용 | ~17.6 GB / 32 GB | 14GB 여유 |
| 속도 | ~65~67 tokens/sec | 27B Q4_K_M 기준 |

---

## 🔧 설정 변경하려면

```bash
nano ~/.config/systemd/user/llama-server.service
```

변경 가능한 주요 옵션:
- `--ctx-size 65536` → 컨텍스트 더 늘리기 (현재 32K, VRAM 추가)
- `--reasoning off` → 생각 모드 끄기 (빠른 응답)
- `--reasoning-budget 512` → 더 깊은 생각
- `--port 8081` → 다른 포트
- `--parallel 4` → 동시 요청 처리

**ctx-size별 VRAM 영향 (Gemma4-31B Q4_K_M 기준, 실측)**:
| ctx-size | VRAM 사용 | 여유 | 한국어 자 수 | 비고 |
|---|---|---|---|---|
| 8,192 | 20.2 GB | 11.9 GB | ~13K | 초기 보수적 |
| 32,768 | 21.8 GB | 10.3 GB | ~52K | 일반 사용 충분 |
| 65,536 | 23.1 GB | 8.8 GB | ~100K | 책 1권 분량 |
| 131,072 (128K) | 25.9 GB | 6.3 GB | ~200K | 책 2권 |
| **262,144 (현재, 256K, 학습 한계)** | **31.6 GB** | **0.5 GB** | **~400K** | 책 4권, GPU 다른 작업 불가 |

### 🎯 모델별 자동 ctx 설정

`ask -l`로 모델 전환 시 ctx-size가 모델 크기 기반으로 자동 조정됩니다 (가중치 + KV cache가 32GB에 맞도록).

| 모델 크기 | 자동 ctx | 한국어 자 수 |
|---|---|---|
| < 22 GB | **262,144** (256K) | ~400K |
| ≥ 22 GB | 131,072 (128K) | ~200K |

**예시**:
- `qwen3.5-4b` (2.6 GB) → 256K 자동
- `qwen3.5-9b` (5.3 GB) → 256K 자동
- `qwen3.6-27b` (16 GB) → 256K 자동
- `gemma-4-31b` (18 GB) → 256K (VRAM 빠듯)

**수동 override** (모델별로 영구 저장):
```bash
ask --show-ctx       # 현재 모델: 적용/저장/자동 보기
ask --set-ctx 65536  # 현재 모델만 64K로 강제
ask --list-ctx       # 모든 모델의 ctx 설정 일람
```
저장 위치: `~/.cache/ask/model_ctx.json`

저장 후 적용:
```bash
systemctl --user daemon-reload
systemctl --user restart llama-server.service
```

---

## 💡 자주 쓰는 시나리오

### 코드 리뷰
```bash
ask "$(cat src/main.py) 위 코드 보안 취약점 찾아줘"
```

### 로그 분석
```bash
journalctl -n 100 | ask "이 시스템 로그에서 문제 찾아"
```

### Git diff 요약
```bash
git diff | ask "이 변경사항을 커밋 메시지 한 줄로 요약"
```

### 번역
```bash
ask "다음을 영어로 번역: 인공지능은 인류의 미래를 바꿀 것이다"
```

### 명령어 도움
```bash
ask "ffmpeg로 mp4를 webm으로 변환하는 명령"
```

---

## 🛑 완전 종료/제거가 필요할 때

### 일시 종료
```bash
systemctl --user stop llama-server.service
```

### 완전 제거
```bash
systemctl --user disable --now llama-server.service
rm ~/.config/systemd/user/llama-server.service
rm -rf ~/models/qwen3.6-27b   # 모델 (16GB 회수)
# rm -rf ~/src/llama.cpp        # 빌드 (필요시)
# ~/.bashrc에서 ask 함수 라인 삭제
```

---

## 🆘 문제 발생시

```bash
# 서비스가 안 뜸
systemctl --user status llama-server.service
journalctl --user -u llama-server.service -n 50

# 응답 없음
curl http://127.0.0.1:8080/health  # 200 OK 떠야 함

# 너무 느림
nvidia-smi  # GPU에 다른 프로세스 점유 중인지 확인

# 메모리 부족 (CUDA OOM)
# → ctx-size 줄이기 또는 다른 GPU 프로세스 종료
```

---


---

부팅 후에도 자동 시작되니, 이제부터는 그냥 `ask "질문"`만 치면 됩니다. 🎉
