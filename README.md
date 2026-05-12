# ask

llama.cpp 로컬 LLM 서버를 터미널에서 빠르게 호출하기 위한 단일 bash 스크립트.

대화 히스토리 자동 유지, 마크다운 렌더링, 모델 다운로드/전환, 시스템 프롬프트 관리 등을 한 명령에 통합.

전체 사용법은 [`manual.md`](./manual.md) 참고.

## 빠른 시작

### 사전 조건 (직접 준비)

이 도구는 **이미 빌드된 `llama-server` 바이너리**를 호출합니다. 빌드는 GPU/CUDA 환경에 따라 천차만별이라 자동화하지 않습니다.

- llama.cpp 빌드 가이드: <https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md>
- 빌드 결과 위치 (기본 가정): `~/src/llama.cpp/build/bin/llama-server`

### 설치 (자동)

```bash
# 1. 저장소 받기
git clone git@github.com:jacobholyman/ask.git ~/Code/Claude/ask
cd ~/Code/Claude/ask

# 2. 자동 설치 스크립트 실행 (Ubuntu/Debian)
./install.sh
```

`install.sh`가 다음을 자동 처리합니다:

1. 의존성 확인/설치 (`jq`, `curl`, `python3-rich`, 선택: `glow`, `huggingface-cli`)
2. `llama-server` 위치 확인
3. 모델 디렉토리(`~/models/`) 생성
4. `systemd` 사용자 서비스 파일 자동 생성 (`~/.config/systemd/user/llama-server.service`)
5. 첫 모델 다운로드 (선택: Qwen3-4B / Qwen3-9B / Gemma-27B / 건너뛰기)
6. 서비스 시작 + 작동 검증
7. `~/.bashrc`에 PATH 자동 등록 (선택)

### 수동 설치

`install.sh`를 쓰지 않으려면 위 1~7번을 직접 수행하면 됩니다. 서비스 파일 예시는 [`manual.md`](./manual.md) 참고.

### 사용

```bash
ask "안녕"
ask --help
ask -l            # 모델 목록 + 전환
askmanual         # 매뉴얼 페이저로 보기 (glow 필요)
```

## 의존성

| 필수 | 용도 |
|---|---|
| `llama.cpp` (`llama-server`, `llama-cli`) | 로컬 LLM 추론 서버 |
| `systemctl --user` | `llama-server.service` 자동 시작/재시작 |
| `curl`, `jq` | OpenAI 호환 API 호출 + JSON 파싱 |
| `bash 4+` | 스크립트 본체 |

| 선택 | 용도 |
|---|---|
| Python `rich` | 마크다운 렌더링 (기본). 없으면 자동으로 `glow` → raw 텍스트 순으로 fallback |
| `glow` | `rich` 없을 때 대체 렌더러, `askmanual` 페이저로도 사용 |
| `huggingface-cli` | `ask -i` 모델 다운로드 기능 |

## 주요 명령 한눈에

| 명령 | 동작 |
|---|---|
| `ask "질문"` | 답변 + 마크다운 렌더링 (이전 대화 기억) |
| `ask -raw "질문"` | raw 스트리밍 (마크다운 변환 없음) |
| `ask -1 "질문"` | 단발 모드 (히스토리 안 쓰고 안 저장) |
| `ask -l` | 설치된 모델 목록 + 인터랙티브 전환 |
| `ask -i <repo> [<quant>]` | HuggingFace에서 모델 다운로드 + 설치 |
| `ask -S "프롬프트"` | 현재 모델의 시스템 프롬프트 설정 |
| `ask --history` | 현재 저장된 대화 보기 |
| `ask --set-ctx N` | context 길이 변경 + 서버 재시작 |

자세한 옵션과 동작 설명은 `ask --help` 또는 [`manual.md`](./manual.md).

## 상태 파일 위치

| 경로 | 내용 |
|---|---|
| `~/.cache/ask/history.json` | 모델별 대화 히스토리 |
| `~/.cache/ask/system_prompts.json` | 모델별 시스템 프롬프트 |
| `~/.cache/ask/model_ctx.json` | 모델별 ctx-size 저장값 |
| `~/.cache/ask/config.json` | 전역 설정 (`--limit` 등) |

## 개발 환경 (참고)

- Ubuntu
- NVIDIA RTX 5090 (32GB VRAM)
- CUDA 13.1
- llama.cpp (CUDA sm_120, Flash Attention 빌드)

## 라이선스

MIT License — [`LICENSE`](./LICENSE) 참고.
