# CI 컴파일 검증 실행 가이드

이 문서는 사용자가 직접 실행하는 절차다. 이 저장소의 어떤 에이전트 세션도 `gh`를 쓰거나 push하지 않는다.

- 검증 대상: 브랜치 `ci-validate/v1` = `2ca5a7b` (패치 0082–0084 포함, 8커밋)
- 상태: 로컬에서는 한 번도 컴파일되지 않았다. 이 브랜치의 목적은 최초 컴파일 검증이다.

## 0. 반드시 읽기

- **`origin`은 업스트림 `dipa-studio/ios-sweet`다 (fetch와 push 모두).** 이 저장소에서 `git push`를 인자 없이 실행하거나 `git push origin ...`을 쓰면 업스트림으로 간다. 하지 말 것.
- **`main`에 push하지 말 것.** `main`으로 push하면 `xnu/patches/**` 변경에 대해 `xnu.yml`이 자동 실행된다 (`.github/workflows/xnu.yml`의 `push: branches: [main]`).
- **PR을 만들어도 빌드는 시작되지 않는다.** 워크플로우에 `pull_request` 트리거가 없다 (`on:`은 `workflow_dispatch`와 `push: main`뿐이다). 빌드는 `gh workflow run`으로만 시작한다.
- **권장 (사용자 결정):** 업스트림 push를 로컬에서 차단한다. `git -C ~/projects/ios-sweet remote set-url --push origin DISABLED`

## 1. CI 워크플로우 정찰

| 항목 | 값 | 근거 |
|---|---|---|
| 워크플로우 파일 | `xnu.yml` 하나 | `.github/workflows/` 목록 |
| 트리거 | `workflow_dispatch` (수동), `push` to `main` (paths: `xnu/patches/**`, 워크플로우 파일) | `xnu.yml:3-22` |
| 실행 환경 | `macos-14` | `jobs.build.runs-on` |
| 기본 입력 | `macos_version=13.5`, `kernel_config=DEVELOPMENT`, `machine_config=SWEET`, `keep_going=true` (`MAKEFLAGS=-k`) | `xnu.yml` inputs |
| 빌드 방식 | `blacktop/darwin-xnu-build` (SHA `663906528d1c…`)가 xnu 소스를 받고, 패치를 적용하고, `make install`로 커널을 컴파일한다 | `build.sh:417` (clone), `426-477` (패치), `720-732` (make) |
| 실제 컴파일 여부 | **예.** XNU 커널 전체를 컴파일한다 | `build.sh:732` |
| 소스 핀 | `release.json` (macos-135) → `xnu-8796.141.3`, `hfs-627.100.6`, `libpthread-514.100.2`. 우리 로컬 검증 태그와 일치 | `build.sh:251`, 원격 `release.json` 실측 |
| KDK | `/Library/Developer/KDKs/KDK_13.5_22G74.kdk` (러너에 있어야 함, 과거 성공 이력 있음) | `build.sh:253` |
| 최근 기록 | run `39117078444` (0061, NOTES.md:69). 정확한 날짜는 NOTES에 없음 | `NOTES.md:69` |
| 워크플로우 최종 수정 | 2026-10-17 (`e4ddc76`) | `git log -- .github/workflows/xnu.yml` |
| 마지막 실행 시각 | 이 머신에는 `gh`가 없어 조회하지 않았다. `gh run list`로 확인 | — |
| 산출물 | `xnu-kernel` (커널 바이너리 + `SHA256SUMS`), `xnu-buildtree` (7일 보관, 단일 파일 재컴파일용) | `upload-artifact` |

## 2. 패치가 적용되는 방식 (성공 판정 기준)

`build.sh`의 `patches()` (426행 이후)는 다음과 같이 동작한다.

1. **스테이지 스크립트** (`0019`, `0020`, `0026`의 `*.sh`)는 `set -o errexit` 아래에서 실행된다 (`build.sh:5`). 실패하면 **빌드가 즉시 중단된다** (크게 실패한다).
2. **패치**는 `git apply --check`가 통과할 때만 적용된다. 실패하면 **경고만 찍고 건너뛴다** (`build.sh:472-477`, `Skipping patch ... (already upstream, previously applied, or malformed)`). **초록불이어도 패치가 빠질 수 있다.**
3. 패치 순서는 사전식 glob 순서다. 우리 `0001-0084`가 먼저 오고, blacktop 자체 패치 8개가 뒤에 온다. 숫자로 시작하는 이름은 문자보다 먼저 정렬된다.
4. `BUILD_WERROR=0`이 커널 make에 전달된다 (`build.sh:732`). 경고는 실패가 아니다.

**로컬에서 검증한 기대치** (정적, 컴파일 아님):
- 우리 패치: 84개 전부 적용 (`0001-0084`)
- blacktop 자체 패치 8개 중 **4개 적용** (`kas_info`, `machine_routines`, `skywalk_ventura`, `syntax_checker_ventura`)
- blacktop 자체 패치 중 **4개는 건너뛴다** (`TrustCache`, `iobuffermemd_monterey`, `skywalk_sonoma`, `syntax_checker_sonoma`). 순정 `xnu-8796.141.3`에서도 똑같이 실패하므로 우리 패치의 문제가 아니다. **CI 로그에도 이 4개의 Skipping 줄이 정상적으로 나온다.**
- 따라서 기대하는 로그 신호: `Applying patch` 88줄, `Skipping patch` 4줄 (위의 blacktop 이름 4개뿐).

## 3. 사용자 실행 명령

### 사전 조건

```sh
sudo pacman -S github-cli          # gh 설치
gh auth login                      # 인증
# 포크 (아직 없다면). 공개 포크가 된다. 공개 저장소는 macOS 러너가 무료다.
gh repo fork dipa-studio/ios-sweet --clone=false
```

포크 웹 페이지에서 **Actions 탭 → "I understand my workflows, go ahead and enable them"** 을 누른다. 포크에서는 Actions가 기본으로 꺼져 있어서, 이 단계를 하지 않으면 `gh workflow run`이 실패한다.

### 포크에 검증 브랜치를 올리고 빌드를 시작한다

`<USER>`를 본인 GitHub 사용자명으로 바꾼다.

```sh
cd ~/projects/ios-sweet
git remote add fork https://github.com/<USER>/ios-sweet.git
git push fork ci-validate/v1          # 포크에만. main이 아니다
gh workflow run xnu.yml -R <USER>/ios-sweet --ref ci-validate/v1 \
  -f macos_version=13.5 -f kernel_config=DEVELOPMENT -f machine_config=SWEET -f keep_going=true
gh run list -R <USER>/ios-sweet --workflow xnu.yml --limit 3    # RUN_ID 확인
gh run watch <RUN_ID> -R <USER>/ios-sweet
```

**선택:** 리뷰용 PR. 빌드를 시작하지 않는다.

```sh
gh pr create -R <USER>/ios-sweet --base main --head ci-validate/v1 \
  --title "CI: validate 84-patch chain compile" --body "First compile validation of patches 0082-0084 (see CI-TRIGGER.md)."
```

### 결과 회수

```sh
mkdir -p ~/ios-sweet-ci
gh run view <RUN_ID> -R <USER>/ios-sweet --log > ~/ios-sweet-ci/run-<RUN_ID>.txt
gh run view <RUN_ID> -R <USER>/ios-sweet --log-failed > ~/ios-sweet-ci/run-<RUN_ID>-failed.txt
```

성공이든 실패든 **패치 적용부터 확인한다.** 초록불만으로 판정하지 않는다.

```sh
F=~/ios-sweet-ci/run-<RUN_ID>.txt
grep -c "Applying patch" $F                       # 기대: 88
grep "Skipping patch" $F                          # 기대: blacktop 이름 4개뿐 (TrustCache, iobuffermemd_monterey, skywalk_sonoma, syntax_checker_sonoma)
grep "Skipping patch" $F | grep -c "/0[0-9][0-9][0-9]-"   # 기대: 0. 0이 아니면 우리 패치 중 하나가 빠진 것이다
grep -n "error:" $F | head -50                    # 컴파일 오류 (있다면)
```

`Skipping patch`에 `0NNN-`가 하나라도 나오면, 그 패치가 실제로 빠진 채 빌드된 것이다. 이 경우 성공으로 치지 않는다.

## 4. 예상 실패 지점 (정적 검토. 컴파일 아님)

심각도: 높음 = 빌드 또는 산출물을 무효로 만든다. 중간 = 빌드를 실패시킬 가능성이 실제로 있다. 낮음 = 경고 또는 정리 항목.

| # | 위치 | 내용 | 심각도 | 근거 | 완화 |
|---|---|---|---|---|---|
| 1 | 0082–0084 `.cpp` (처음 컴파일) | 헤더로 확인한 API는 대부분 맞다 (아래 5절). 남은 위험은 실제 컴파일 세부에서 나온다 | **중간** | 처음 컴파일되는 코드 | 실패 시 `xnu-buildtree` 아티팩트로 로컬 재컴파일 |
| 2 | 0081 `bsd/dev/sweet_usb.c` | 빌드 기록이 없다. 새 include (`net/if_media.h`, `net/dlil.h`)와 `SIOCGIFMEDIA`, `KEV_DL_LINK_ON`은 헤더에 존재함을 확인 | 낮음~중간 | `bsd/net/if_media.h`, `bsd/net/net_kev.h:67`, `bsd/sys/sockio.h:136` | 로그에서 `sweet_usb` 오류 확인 |
| 3 | 패치 건너뜀 (무음) | 우리 패치가 `git apply --check`에서 실패하면 경고만 찍고 빌드가 성공한다 | **높음** (성공 오판) | `build.sh:472-477` | 2절의 grep 검사 |
| 4 | 스테이지 스크립트의 외부 fetch | GitHub `libpthread`/`hfs`와 `bearssl.org`에서 받는다. 실패하면 빌드가 즉시 중단된다 (크게 실패) | 낮음 | `build.sh:5`. 과거 CI에서 0019/0020/0026 성공 이력 | 재실행 |
| 5 | 포크 Actions 비활성 | 포크는 Actions가 꺼진 상태로 시작한다. `gh workflow run`이 실패한다 | 중간 (환경) | GitHub 기본 동작 | 3절 사전 조건에서 켠다 |
| 6 | macOS 러너 분 | 포크가 공개면 무료다. 비공개면 분 한도나 결제 문제로 실패할 수 있다 (NOTES에 과거 사례 있음) | 중간 (환경) | `NOTES.md` "Repo made PUBLIC" 항목 | 공개 포크 사용 |
| 7 | KDK 경로 | `/Library/Developer/KDKs/KDK_13.5_22G74.kdk`가 러너에 없으면 `KDKROOT not found`로 실패한다 | 낮음 | `build.sh:253`. 과거 13.5 빌드 성공 이력 | 로그 확인 |
| 8 | 게이트 값 검사 (런타임) | `PE_parse_boot_argn(name, NULL, 0)`은 이름의 존재만 본다. `sweetgpu=0`도 게이트를 연다 | 낮음 (컴파일과 무관) | `pexpert/gen/bootargs.c` `max_len == 0` 분기 | 다음 세션에서 값 검사로 수정 |
| 9 | 가드 관행 | 0082–0084 `.cpp`에는 `#if defined(SWEET)` 가드가 없다. 기존 파일은 `SweetCPU.cpp:8`, `SweetPlatformExpert.cpp:8`에서 가드한다 | 낮음 | CI는 SWEET 전용이라 영향 없음 | 다음 세션에서 맞춘다 |
| 10 | 미사용 include와 함수 | `SweetGPU.cpp`의 `kern/clock.h`, `IOMapper.h`, 오디오의 `codecReset`/`slaveAttach`는 사용되지 않는다 | 낮음 (경고) | `BUILD_WERROR=0` | 없음 |
| 11 | `printf("%zu")` (Wi-Fi) | xnu printf가 `z` 수식자를 지원한다 | 낮음 | `osfmk/kern/printf.c:366` 확인 | 없음 |

## 5. 정적 검토로 확인한 API (헤더 grep, 컴파일 아님)

| 사용처 | 확인 내용 | 위치 |
|---|---|---|
| `IOBufferMemoryDescriptor::withOptions` | `OSPtr<T>`를 반환한다. `IOKIT_ENABLE_SHARED_PTR`이 정의되지 않아 `T*`와 같다 | `IOBufferMemoryDescriptor.h:192`, `OSPtr.h`, 빌드 설정에 매크로 없음 |
| `kIOMemoryKernelUserShared` | 파일 스코프 enum에 있다 (클래스 스코프 아님) | `IOBufferMemoryDescriptor.h:42` |
| `getPhysicalAddress()` | `IOMemoryDescriptor`에 있다 | `IOMemoryDescriptor.h:713` |
| `IOMemoryMap::getVirtualAddress/getLength` | `IOMemoryMap` 클래스(877행) 안에 있다 | `IOMemoryDescriptor.h:907, 937` |
| `mapDeviceMemoryWithIndex`, `registerService` | 선언과 반환 타입이 맞다 | `IOService.h:1335, 642` |
| `probe`, `start`, `stop`, `init`, `free` | 오버라이드 시그니처가 맞다 | `IOService.h:651, 659, 665, 745, 755` |
| `APPLE_KEXT_OVERRIDE` / `override` | `-std=gnu++1z`이므로 `override`를 써도 된다 | `OSMetaClass.h:226`, `MakeInc.def:574` |
| `OSSafeReleaseNULL`, `OSDeclareDefaultStructors` | 정의되어 있다 | `OSMetaClass.h:464, 1887` |
| `IODelay` | 정의되어 있다 | `IOLib.h:590` |
| `PE_parse_boot_argn` | `max_len == 0`이면 복사하지 않고 존재 여부만 돌려준다 (NULL 포인터 안전) | `pexpert/gen/bootargs.c` |
| `page_size` | 선언되어 있다 | `osfmk/mach/vm_param.h:681` |
| IOService 이름 충돌 | `powerOn`, `powerOff`, `enable`, `disable`, `getHardwareAddress`는 `IOService.h`에 없다 | `grep` 0건 |
| `BUILD_WERROR` | `0`이므로 경고는 실패가 아니다 | `build.sh:712-732` |

## 6. 로그 판독 체크리스트

1. `Running script` 줄이 3개 (`0019`, `0020`, `0026`)이고 오류가 없다.
2. `Applying patch` 줄이 **88개**다 (우리 84 + blacktop 4).
3. `Skipping patch` 줄은 blacktop 이름 4개뿐이다. `0NNN-`가 하나라도 있으면 실패로 본다.
4. `error:` 줄이 없다. `make install`이 성공했다.
5. 아티팩트 `xnu-kernel`에 커널 바이너리와 `SHA256SUMS`가 있다.
6. 실패하면 `error:` 줄을 파일 단위로 모은다. `xnu-buildtree`를 받아 실패한 컴파일 명령을 로컬에서 재현한다 (`AGENTS.md` 절차).
