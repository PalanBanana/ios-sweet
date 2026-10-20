# ios-sweet 로드맵

기준일: 2026-10-19. 이 문서는 **소스 근거가 있는 것**과 **실기에서 확인해야 하는 것**을 나눠 적는다. 소스 근거가 있다는 말은 하드웨어에서 동작한다는 뜻이 아니다.

근거 소스 (로컬 전용, `~/refs/`, 저장소 밖):
- XNU: `apple-oss-distributions/xnu` tag `xnu-8796.141.3`
- Mesa: `src/freedreno/registers/adreno/*.xml`
- Linux: `drivers/gpu/drm/msm/`, `drivers/net/wireless/ath/ath10k/`, `sound/soc/codecs/wcd937x*`

## 1. 현재 완료 (소스 확정 기준)

### 0082 GPU (`MsmGpuAdreno618`)
- **GPU 실동작: scaffold→scaffold+실 register write 가능.** 세션 12 (`f6bdb2b`)에서 DT 값으로 재작성했다. 실제로 동작하는 것은 아니다. zap, 클록/GDSC, SMMU, CP 시작은 미구현이고, 컴파일 기록도 없다.
- 레지스터 오프셋은 **dword 인덱스**다 (`adreno_gpu.h:766`, `mmio + (addr << 2)`). 주요 RBBM/CP/GBIF 오프셋은 `a6xx.xml`, `adreno_common.xml`로 확정.
- 리셋 시퀀스 (`a6xx_gpu.c:2128-2131`), `RBBM_INT_0_MASK = 0` (`a6xx_gpu.c:1849`), CP_RB_BASE는 lo 다음 hi (`msm_gpu.h:692-698`).
- `CP_RB_CNTL` 기본값 `0x20C` (`msm_gpu.h:306-311`).
- 칩 ID는 레지스터가 아니라 카탈로그 상수 `0x06010800` (`a6xx_catalog.c:763`). zap 파일명 `a615_zap.mbn` (`a6xx_catalog.c:774`).
- 프레임 제출은 `kIOReturnUnsupported`다. `CP_MEM_TO_MEM`은 dword만 복사하므로 표면을 옮길 수 없다 (`adreno_pm4.xml:1368`).
- 부트 인수 게이트 `sweetgpu=1`. 세션 12부터 이 게이트가 열리면 레지스터를 쓴다 (리셋, INT 마스크, SECVID, CP_RB). 게이트 기본값은 닫혀 있다.
- DT 값 (세션 12, `sweet.dts`): reg 창 4개 (17752), IRQ SPI 300 (17754), speed bin qfprom `0x41a0`, mask `0x1fe00000`, shift 21 (17783), 주파수 표 5개 bin (17821–18117), SECVID 쿼크 (17759).

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
- `CP_RB_CNTL`의 `NO_UPDATE` 비트: `hw_apriv`에 따라 달라진다 (`a6xx_gpu.c:1452-1456`). 세션 13: 이 칩은 `HAS_HW_APRIV`가 없어 Linux는 `0x0800020C`를 쓴다. 0082의 `0x20C`와 다르다 (세션 14 결정).
- 프레임 제출 재설계: `CP_INDIRECT_BUFFER` 기반 command stream과 fence.
- zap: DT의 `pil_gpu`는 GPU 노드가 참조하지 않는다 (`sweet.dts:17674-17678`). Linux는 자식 `zap-shader`만 찾으므로 (`adreno_gpu.c:49`) 이 DT에서는 `-ENODEV` 경로 (`a6xx_gpu.c:1515-1516`)가 된다. secure mode가 필요한 GPU인지는 미확정이다. PAS id 0x0d는 Linux `GPU_PAS_ID` 13 (`a6xx_gpu.c:17`)과 같아서 GPU zap 노드일 가능성이 높다. 다운스트림 조회 방식은 로컬과 웹 검색에서 확인하지 못했다 (세션 13). 펌웨어 `a615_zap.*`는 SSD의 Android vendor 파티션에 있고 아직 확보하지 않았다.
- 클록과 GDSC: core_clk, rbbmtimer_clk, mem_clk, mem_iface_clk, gmu_clk (`sweet.dts:17768`); vddcx 0x1c5 (gpu_cx_gdsc), vdd 0x24e (gpu_gx_gdsc) (17777–17778). XNU에 제어 경로가 없다.
- SMMU: `arm,smmu-kgsl@5040000` (`sweet.dts:10589`). GPU 주소 번역은 미구현이다.
- TSB와 ADDR_MODE: Linux hw_init은 `RBBM_SECVID_TSB_*`를 0으로, `*_ADDR_MODE_CNTL`을 1로 쓴다 (`a6xx_gpu.c:1210-1236`). 재작성은 쓰지 않는다.
- CP_RB_RPTR_ADDR는 쓰지 않는다 (CP 시작 전에는 불필요). INT 마스크는 0이다 (Linux hw_init은 `A6XX_INT_MASK`, `a6xx_gpu.c:1436-1437`).
- 칩 ID: Mesa에 레지스터가 없어 읽기 전용 검증을 할 수 없다.
- speed bin: 이 폰의 값은 미확인이다. 표에 없으면 start가 실패한다. bin 0xa7의 initial level은 센티넬이라 그 bin은 항상 거부된다.

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
| 2026-10-19 (세션 8) | 스위프트 clang과 qemu 설치 | **첫 CI run 후로 연기** | 설치만으로는 검증이 늘지 않는다. `xnu-cc.py`는 CI 로그와 buildtree가 필요하고, QEMU는 커널이 필요하다. 정적으로 할 수 있는 검사 (include, 심볼, 시그니처, 접근성)는 세션 8에서 끝냈다 (확정 오류 0) |
| 2026-10-19 (세션 8) | `xnu-cc.py` 수정 | **제안만, 미적용** | 환경변수 오버라이드 (`XNU_CC_CLANG`, `XNU_CC_CI_DXB`)와 `--help`. 도구 수정은 사용자 승인 사항 |
| 2026-10-19 (세션 9) | CI 게이트 린트 (actionlint, shellcheck) | **완료, 오류 0** | 워크플로우 info 1 (표시용 SC2012), 스크립트 경고 4 (CI 판정 무관). 실 CI 로그 검증은 첫 run 대기 |
| 2026-10-19 (세션 9) | 첫 run 판정 하네스 | **준비 완료** | `tools/post-ci-analyze.sh`, 판정 5종, fixture 5개, 테스트 7/7. 첫 run 로그로 검증 필요 |
| 2026-10-19 (세션 12) | 0082 재작성 | **완료 (`f6bdb2b`), 미컴파일** | DT 값 반영, stop 게이트 버그 수정, 링 32 KiB로 `0x20C`와 일치, zap은 Linux `-ENODEV` 경로. 체인 84/84, 체크 18/18 |
| 2026-10-19 (세션 12) | 첫 CI run 판정 | **PASS (로그 재확인)** | 적용 88, 실패 0, 진단 0. 빌드 커밋과 실행 ID는 로그에 없다 |
| 2026-10-20 (세션 13) | CI 준비와 연구 | **코드 변경 없음** | push 대상은 `HEAD` (로컬 `ci-validate/v1`은 `fd539b9`). `workflow_dispatch`로 수동 실행. NO_UPDATE 불일치와 TSB/ADDR_MODE 표는 세션 14 입력 |
| 2026-10-20 (세션 14) | CI 결과 확인 | **Case N (CI 미실행)** | fork `ci-validate/v1` = `fd539b9`, 새 run 로그 없음. NO_UPDATE 의미 정정 (하드웨어 RPTR 섀도를 끈다). TSB/ADDR_MODE 적용 초안은 승인 전 미적용 |
| 2026-10-20 (세션 15) | CI 결과 확정 | **PASS (run `39350775805`, 빌드 커밋 `ad20b73`)** | 0082 재작성 (`f6bdb2b`, `a42cd8b`) 컴파일과 링크 통과, 아티팩트 3종. 승인 대기: 펌웨어 조사, TSB 3개, ADDR_MODE 12개. NO_UPDATE는 세션 16 |
| 2026-10-20 (세션 16) | 승인 2+3과 readFuse 정리 | **커밋 `580e857`, CI 대기** | TSB 3개 레지스터와 ADDR_MODE 12개 쓰기 (실행 경로 없음). `readFuse` `-Wcast-align` 정리 (warning-only, 0x41a0 정렬 static_assert). 승인 1 (펌웨어 조사)은 폰 미연결로 미실행. 승인 4 (NO_UPDATE) 보류 |
| 2026-10-20 (세션 16, 분석) | shim SCM, hw_init 매핑, personality 준비 | **코드 변경 없음** | shim에 SCM/PAS 없음 (SMC는 PSCI뿐). hw_init 쓰기 약 140개 중 0082 구현 19개. GMU·SQE·SCM·GDSC가 다음 장벽. personality는 게이트 닫힘에서 레지스터를 건드리지 않음. QEMU·clang 설치는 승인 대기 |

참고: 원 요청의 날짜 자리표시(`2024-XX-XX`)는 실제 날짜 2026-10-19로 적었다.

## 5. 다음 세션 후보 (우선순위)

- **P0:** CI 컴파일 검증 성공 (첫 run PASS, 로그 재확인). **GPU 상태: CI 컴파일 PASS** (run `39350775805`, 빌드 커밋 `ad20b73`). run `39359712049` (빌드 커밋 `dec211a`, `580e857` 포함)은 컴파일 PASS이고 `SweetGPU` 경고는 0이다. 실행 동작은 미검증이다. push 명령은 `git push fork HEAD:ci-validate/v1`이다 (`CI-PRECHECK.md` 세션 13). `ci-validate/v1`을 포크에서 실행하고 로그에서 `Skipping patch` 0건을 확인한다. 절차는 `CI-TRIGGER.md`.
  - 로컬 컴파일과 QEMU는 첫 CI run 이후로 연기한다 (입력 부재). 결정 필요: 스위프트 clang 설치 여부 (`xnu-cc.py`), `qemu-system-arm` 설치 여부 (사용자 승인 필요).
- **P0 후속 (세션 5 완료):** 게이트 값 검사 (`21b42d0`), SWEET 가드 (`723c65b`), 패치 skip 검사 (`66ea9a5`). 남은 것: 0081 빌드 확인 (CI 로그).
- **P1:** GPU 하드웨어 bring-up. DT 값은 세션 12에서 확정됐다. 남은 것: 클록/GDSC 제어, SMMU, GBIF slice id, speed bin 실측, zap 필요 여부 (SSD 마운트 후 펌웨어 확인).
- **P2:** QRTR 프로젝트 착수 여부 — 사용자 결정.
- **P3:** SoundWire 프로젝트 착수 여부 — 사용자 결정.
