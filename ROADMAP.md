# ios-sweet 로드맵

기준일: 2026-10-19. 이 문서는 **소스 근거가 있는 것**과 **실기에서 확인해야 하는 것**을 나눠 적는다. 소스 근거가 있다는 말은 하드웨어에서 동작한다는 뜻이 아니다.

근거 소스 (로컬 전용, `~/refs/`, 저장소 밖):
- XNU: `apple-oss-distributions/xnu` tag `xnu-8796.141.3`
- Mesa: `src/freedreno/registers/adreno/*.xml`
- Linux: `drivers/gpu/drm/msm/`, `drivers/net/wireless/ath/ath10k/`, `sound/soc/codecs/wcd937x*`

## 1. 현재 완료 (소스 확정 기준)

### 0082 GPU (`MsmGpuAdreno618`)
- 레지스터 오프셋은 **dword 인덱스**다 (`adreno_gpu.h:766`, `mmio + (addr << 2)`). 주요 RBBM/CP/GBIF 오프셋은 `a6xx.xml`, `adreno_common.xml`로 확정.
- 리셋 시퀀스 (`a6xx_gpu.c:2128-2131`), `RBBM_INT_0_MASK = 0` (`a6xx_gpu.c:1849`), CP_RB_BASE는 lo 다음 hi (`msm_gpu.h:692-698`).
- `CP_RB_CNTL` 기본값 `0x20C` (`msm_gpu.h:306-311`).
- 칩 ID는 레지스터가 아니라 카탈로그 상수 `0x06010800` (`a6xx_catalog.c:763`). zap 파일명 `a615_zap.mbn` (`a6xx_catalog.c:774`).
- 프레임 제출은 `kIOReturnUnsupported`다. `CP_MEM_TO_MEM`은 dword만 복사하므로 표면을 옮길 수 없다 (`adreno_pm4.xml:1368`).
- 부트 인수 게이트 `sweetgpu=1`.

### 0083 Wi-Fi (`Wcn3990Controller`)
- ath10k 기준 SNOC + QMI 구조로 재작성. GENI FIFO 모델은 제거 (반증됨).
- 레일 이름 5개 확정 (`snoc.c:48-54`): `vdd-0.8-cx-mx`, `vdd-1.8-xo`, `vdd-1.3-rfa`, `vdd-3.3-ch0`, `vdd-3.3-ch1`. 클록 (`snoc.c:56-58`): `cxo_ref_clk_pin`, `qdss`.
- 전원 순서: pwrseq `wlan` 우선, 그다음 레귤레이터, 그다음 클록 (`snoc.c:1022-1048`). pwrseq가 없을 때만 5개 레일을 드라이버가 직접 관리 (`snoc.c:1804-1820`).
- QMI 핸드셰이크 순서: server arrive (`qmi.c:808`), MSA ready (`qmi.c:918`), WLAN enable (`qmi.c:515`). SNOC membase (`snoc.c:1322`).
- 게이트 `sweetwifi=1`은 QMI 전송이 없으므로 레일을 켜지 않고 거부한다.

### 0084 Audio (`SweetWcd9375Audio`)
- **미착수.** P0 검증에서 SLIMBUS 가정과 오프셋을 반증했다 (`wcd937x.c`에 SLIMBUS 참조 0건; 레지스터는 SoundWire 16-bit 주소, `wcd937x.h:297-305`).
- 게이트 `sweetaudio=1`은 거부한다.

### 패치 체인
- 0001–0084 전체가 xnu-8796.141.3에서 `git apply --check` 및 `git apply`를 통과한다 (정적 확인, `files.arm64` 앵커 22/23/24행 확정).
- 스테이지 스크립트 0019/0020/0026은 `TargetConditionals.h` placeholder로 실행했다. 컴파일은 하지 않았다.
- **컴파일 기록**: 0080까지 CI 빌드 기록이 NOTES에 있다 (0079 커널은 폰에서 부팅 확인). 0081 빌드 기록은 없다. 0082–0084는 한 번도 컴파일되지 않았다.

## 2. 미완료 — 하드웨어 bring-up 필요

### GPU
- GBIF_SCACHE_CNTL0/1 값: 커널이 런타임 LLCC slice id에서 계산한다 (`a6xx_gpu.c:1980-2050`). 이 보드의 slice id가 필요하다.
- `CP_RB_CNTL`의 `NO_UPDATE` 비트: `hw_apriv`에 따라 달라진다 (`a6xx_gpu.c:1453-1455`).
- 프레임 제출 재설계: `CP_INDIRECT_BUFFER` 기반 command stream과 fence.
- zap 펌웨어 전달: 파일은 SSD의 Android vendor 파티션에 있다. 부트 인수 또는 예약 메모리로 넘기는 방식을 정해야 한다.

### Wi-Fi
- pwrseq `wlan` 제공 경로 (DT/ADT 노드) 확보.
- 레일 전압값 (DT에서 확인, 미확정).
- SNOC membase의 IOKit 인덱스 매핑 (ADT 노드, 미확정).
- QMI 실구현 — **QRTR 선결** (3-1).

### 공통
- 세 부트 인수 게이트의 실기 검증.
- 게이트 값 검사: 세션 5에서 수정됨 (`21b42d0`). 값이 정확히 1일 때만 연다.
- SSD 마운트: `backup/`, `dtb/`, 펌웨어 blob.

**선결 자원:** SSD 마운트, firmware blob (`a615_zap.mbn`, WLAN 펌웨어/BDF), DT 전압값.

## 3. 미완료 — 선결 인프라 프로젝트 (별도 세션 규모)

### 3-1. QRTR / remoteproc (XNU용)
- **막는 것:** Wi-Fi QMI 전체. ath10k는 `qmi_handle_init`으로 QRTR 소켓을 연다 (`qmi.c:1098`).
- **필요한 선행 지식:** QRTR 패킷 프로토콜, QMI TLV 인코더/디코더, 원격 프로세서 기동, MSA 메모리 권한 설정 (`qmi.c:32-120`).
- **참조 소스:** `qmi.c`, `qmi_wlfw_v01.c` (확보됨). `net/qrtr`, remoteproc, SMP2P (미확보).
- **작업 분해 (예상):** (1) QRTR 송수신 (2) QMI 코덱 이식 (3) wlanfw 서비스 lookup과 indication (4) MSA 권한과 원격 프로세서 기동 (5) SNOC CE 연결.
- **규모:** 멀티 세션 (추정. 근거는 미확정).

### 3-2. SoundWire 슬레이브 설계 (WCD9375)
- **막는 것:** 오디오 전체.
- **필요한 선행 지식:** SoundWire 프로토콜 (enumeration, 슬레이브 레지스터 읽기/쓰기), `wcd937x.h`의 레지스터 맵 (297행 이후), 코덱 초기화 (`wcd937x.c`).
- **참조 소스:** `wcd937x-sdw.c`, `wcd937x.c`, `wcd937x.h` (확보됨). SoundWire 마스터 컨트롤러 드라이버 (미확보).
- **작업 분해 (예상):** (1) SoundWire 마스터 MMIO와 enumeration (2) 슬레이브 R/W (3) 코덱 초기화 (4) 라우팅. ADM/APR 경로는 ADSP와 통신할 가능성이 높다 (`sound/soc/qcom/qdsp6`, 미확보·미확인). 그렇다면 3-1과 같은 원격 프로세서 인프라에 의존한다.
- **규모:** 멀티 세션 (추정).

## 4. 결정 사항 로그

| 날짜 | 항목 | 결정 | 근거 |
|---|---|---|---|
| 2026-10-19 | Wi-Fi QRTR/remoteproc | **defer.** 이번 세션에서 손대지 않는다 | 멀티 세션 규모. stub 위에 stub을 쌓는 것을 막는다 |
| 2026-10-19 | Audio SoundWire 재설계 | **defer** | 별도 프로젝트. 검증되지 않은 토대 위에 쌓지 않는다 |
| 2026-10-19 | 다음 작업 | **최초 CI 컴파일 검증을 먼저** | 8커밋 unpushed. 0082–0084 미컴파일 |
| 2026-10-19 | 검증 브랜치 | `ci-validate/v1`. **포크에만 push, main 금지** | `origin`은 업스트림이다. 세션 5에서 push URL을 DISABLED로 설정 |
| 2026-10-19 (세션 5) | QRTR/SoundWire | **deferred 유지** (재확인) | 세션 5 지시. 착수하지 않음 |
| 2026-10-19 (세션 7) | 로컬 컴파일 (`xnu-cc.py`)과 QEMU 스모크 | **미검증 (입력 부재)** | CI 로그와 `xnu-buildtree`, 스위프트 clang, `qemu-system-aarch64`, 커널이 이 머신에 없다. 우회하지 않는다. 첫 CI run 후 재시도 (`CI-PRECHECK.md` 항목 3, 4) |

참고: 원 요청의 날짜 자리표시(`2024-XX-XX`)는 실제 날짜 2026-10-19로 적었다.

## 5. 다음 세션 후보 (우선순위)

- **P0:** CI 컴파일 검증 성공. `ci-validate/v1`을 포크에서 실행하고 로그에서 `Skipping patch` 0건을 확인한다. 절차는 `CI-TRIGGER.md`.
  - 로컬 컴파일과 QEMU는 첫 CI run 이후로 연기한다 (입력 부재). 결정 필요: 스위프트 clang 설치 여부 (`xnu-cc.py`), `qemu-system-arm` 설치 여부 (사용자 승인 필요).
- **P0 후속 (세션 5 완료):** 게이트 값 검사 (`21b42d0`), SWEET 가드 (`723c65b`), 패치 skip 검사 (`66ea9a5`). 남은 것: 0081 빌드 확인 (CI 로그).
- **P1:** SSD 마운트 후 GPU 하드웨어 bring-up (펌웨어, DT 값, GBIF slice id).
- **P2:** QRTR 프로젝트 착수 여부 — 사용자 결정.
- **P3:** SoundWire 프로젝트 착수 여부 — 사용자 결정.
