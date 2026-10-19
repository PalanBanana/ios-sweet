# CI 사전 점검 (precheck)

`CI-TRIGGER.md` §3의 명령을 실행하기 전에 로컬에서 확인할 여덟 항목이다. 판정은 세 가지다.

- **통과**: 이 머신에서 실제로 확인했다.
- **실패**: 확인했고 맞지 않는다. 옆 칸에 조치를 적었다.
- **미검증**: 확인할 입력이 이 머신에 없거나, 첫 CI run이 있어야 확인된다. 사유를 적었다.

기준 시점: 2026-10-19, 세션 7. 기준 커밋: `ci-validate/v1`의 HEAD (`git rev-parse --short ci-validate/v1`).

## 여덟 항목

| # | 항목 | 판정 | 근거 또는 조치 |
|---|---|---|---|
| 1 | `git apply --check` 84/84 | **통과** | 깨끗한 `xnu-8796.141.3` 워크트리에서 스테이지 스크립트 3개를 먼저 실행한 뒤 패치 84개를 CI 순서로 적용. 스테이지는 SDK 헤더를 placeholder로 받으므로 이 확인은 경로와 문맥만 본다. 0082–0084의 `files.arm64` 앵커는 23/24/25행. 조치: 패치를 고쳤다면 같은 절차로 다시 확인 |
| 2 | `tools/test-check-patch-log.sh` 17/17 | **통과** | 합성 로그 17개 케이스 전부 통과. 실제 CI 로그로는 아직 검증되지 않았다 |
| 3 | `tools/xnu-cc.py`로 0082–0084 컴파일 | **미검증** | 사유 세 가지. (a) 입력 부재: CI 로그와 `xnu-buildtree`가 없다. 이 트리로는 CI run이 한 번도 없었다. (b) 도구가 `~/swift/usr/bin/clang` (swiftlang 포크)을 하드코딩한다 (`tools/xnu-cc.py:25`). 이 머신에는 없다. (c) 빌드 디렉터리 (`build/xnu.obj`의 Makefile과 `meta_features.h`)는 xnu 빌드가 만든다. 그 빌드의 SDK 해석은 `/usr/bin/xcrun`에 기대며 (`makedefs/MakeInc.cmd:108,124`), 이 머신에는 `/usr/bin/xcrun`이 없다. `--help`는 지원되지 않는다 (`sys.argv[2]`에서 IndexError). 사용법은 `tools/xnu-cc.py` 모듈 설명문에 있다. 조치: 첫 CI run 후 아래 "첫 실행 후 명령"으로 재시도. 1차 입력은 `xnu-build-log`, 2차는 `xnu-buildtree` |
| 4 | `tools/qemu-sweet.py` 스모크 | **미검증** | 사유 세 가지. (a) `qemu-system-aarch64`가 없다 (`qemu-sweet.py:184`가 호출). (b) 커널 산출물이 없다 (`xnu-kernel` 아티팩트는 CI가 만든다). (c) payload는 `mkpayload.py KERNEL ADT`로 만들며 커널이 필요하다. ADT는 `tools/mkadt.py OUT --qemu`로 로컬에서 만들 수 있다 (확인: 4164 바이트, `/product` 노드 없음 경고). 조치: `qemu-system-arm` 설치 (사용자 승인 필요), CI 커널 확보, payload 생성 후 `--kernel`과 `--fail-on-panic`으로 실행 |
| 5 | `origin` push URL `DISABLED` | **통과** | `git remote -v`: fetch는 upstream, push는 `DISABLED`. `git push --dry-run origin main`이 거부됨 |
| 6 | `ci-validate/v1`의 기대 커밋 | **통과** | 세션 7 마감 HEAD를 가리킨다. push 직전에 `git rev-parse --short ci-validate/v1`이 기대 값과 같은지 확인 |
| 7 | 첫 CI run에서만 확인되는 항목 | **미검증** | 아래 표 7-1 |
| 8 | `CI-TRIGGER.md` §3 명령 블록 | **통과** | `macos_version`, `kernel_config`, `machine_config`, `keep_going` 네 입력이 `xnu.yml`의 `workflow_dispatch` 입력과 일치. `--ref ci-validate/v1` 사용. 명령 목록 (`gh run list/watch/view`) 확인 |

### 7-1. 첫 CI run에서 확인할 다섯 항목

| 항목 | 판정 | 근거 | 확인 방법 |
|---|---|---|---|
| `gh run view --log`의 열 구분 (탭 또는 공백) | **미검증** (근거 부분 있음) | `tools/xnu-cc.py:36`의 정규식 `^build\s+Build\s+\S+\s+`은 탭과 공백을 모두 허용한다. 그래서 기존 `awk -F'\t'`은 탭이 아니면 틀린다. 플레이북은 기본 FS 방식 (`awk '$1=="build" && $2=="Build"'`)을 쓴다 | `head -n 3 run.txt \| cat -A`. 탭이면 `^I`가 보인다 |
| `if: always()` verify 단계 실행 | **미검증** (문서 기준) | GitHub 문서: `always()`는 앞 단계가 실패해도 실행된다. 이 머신에서 Actions를 실행할 수 없다 | 로그에 `Verify patch application` 단계와 `SWEET_PATCH_SUMMARY` 줄이 있는지 |
| `xnu-build-log` 아티팩트 생성 | **미검증** | 워크플로우 `Upload build log` 단계 (`if: always()`) | `gh api repos/<USER>/ios-sweet/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[].name'` |
| 실패 run에 `xnu-kernel` 없음 | **미검증** (규칙상 기대) | `xnu-kernel` 업로드는 `if: success()`. 실패 run에 있으면 워크플로우가 깨진 것 | 위 명령으로 실패 run의 목록 확인. 성공 run에는 `xnu-kernel`이 있어야 한다 |
| SUMMARY 줄 값 | **미검증** | 기대: `SWEET_PATCH_SUMMARY: result=PASS applied=88 skipped=4 baseline_skipped=4 failed=0`. 합성 로그로만 확인했다 | `grep SWEET_PATCH_SUMMARY run.txt` |

## 첫 실행 후 명령 (항목 3과 4의 재시도)

CI가 끝나고 빌드 로그와 빌드 트리를 받은 뒤 쓴다. 경로는 예시다.

```sh
RUN=<RUN_ID>; R="-R <USER>/ios-sweet"; D=~/ios-sweet-ci/run-$RUN-artifacts
gh run download $RUN $R -n xnu-build-log -D $D           # build.log
gh run download $RUN $R -n xnu-buildtree -D $D           # buildtree.tgz
mkdir -p $D/bt && tar xzf $D/buildtree.tgz -C $D/bt

# 항목 3: 스위프트 포크 clang이 있을 때만 (~/swift/usr/bin/clang)
cd ~/projects/ios-sweet
python3 tools/xnu-cc.py $D/build.log $D/bt \
  iokit/Kernel/arm/SweetGPU.cpp iokit/Kernel/arm/SweetWifi.cpp iokit/Kernel/arm/SweetWcd9375Audio.cpp --per-file
```

`tools/xnu-cc.py`의 `CI_DXB`는 `/Users/runner/work/ios-sweet/ios-sweet/dxb`로 고정되어 있다 (`tools/xnu-cc.py:23`). 포크의 저장소 이름이 `ios-sweet`가 아니면 명령을 하나도 찾지 못한다.

## 세션 7 결과 요약

- 항목 1, 2, 5, 6, 8: 통과.
- 항목 3, 4, 7: 미검증. 사유와 조치는 위 표에 있다.
- 로컬 컴파일과 QEMU 스모크는 입력이 없어서 실행하지 않았다. 억지 우회는 하지 않았다.

## 세션 8: 정적 컴파일 대조 (컴파일러 없음)

0082–0084 (`SweetGPU.cpp`/`.h`, `SweetWifi.cpp`/`.h`, `SweetWcd9375Audio.cpp`/`.h`)를 `~/refs/xnu-sweet`의 적용된 트리에서 xnu-8796.141.3 헤더와 대조했다. 컴파일은 하지 않았다.

| 파일 | include | 심볼 | 시그니처 | 접근성 | 판정 |
|---|---|---|---|---|---|
| `SweetGPU.cpp` | 8/8 해결 | XNU 이름 30개 전부 선언됨 | 멤버 12/12 일치, 호출 29건 해결 | 멤버 함수 전부 `public:` | 확정 오류 0 |
| `SweetGPU.h` | 3/3 해결 | (헤더) | 메서드 선언 일치 | `public:` | 확정 오류 0 |
| `SweetWifi.cpp` | 6/6 해결 | XNU 이름 전부 선언됨 | 멤버 14/14 일치, 호출 24건 해결 | `public:` | 확정 오류 0 |
| `SweetWifi.h` | 2/2 해결 | (헤더) | 일치 | `public:` | 확정 오류 0 |
| `SweetWcd9375Audio.cpp` | 6/6 해결 | XNU 이름 전부 선언됨 | 멤버 13/13 일치, 호출 26건 해결 | `public:` | 확정 오류 0 |
| `SweetWcd9375Audio.h` | 2/2 해결 | (헤더) | 일치 | `public:` | 확정 오류 0 |

**결과: 확정 오류 0건, 수정 0건.** 0082–0084에서 수정할 것은 없었다.

확인 방법 (모두 소스 대조, 실행 아님):
- include: 27개 전부 해결. 검색 루트는 `iokit/`, `libkern/`, `pexpert/`, `osfmk/`, `bsd/`와 `EXTERNAL_HEADERS/`다 (`makedefs/MakeInc.def:884-893`의 INCFLAGS). `<libkern/libkern.h>`는 `bsd/libkern/libkern.h`로 해결되며, 같은 include를 쓰는 상위 파일이 있다 (`iokit/Kernel/IONVRAMV3Handler.cpp`). COMPONENT_IMPORT_LIST가 bsd를 포함한다 (`makedefs/MakeInc.def:57`).
- 심볼: 드라이버가 선언하지 않은 식별자 중 XNU 이름 30개를 헤더에서 찾았다. `kIODirectionInOut`은 `IOMemoryDescriptor.h:65`, `SInt32`는 `libkern/libkern/OSTypes.h:68`, `page_size`는 `osfmk/mach/vm_param.h:681`, `printf`는 `bsd/libkern/libkern.h:172`과 `osfmk/kern/misc_protos.h:173`에 있다. 로컬 이름 29개는 XNU 매크로와 충돌하지 않는다. 드라이버 클래스 이름 3개도 다른 곳에서 정의되지 않는다.
- 시그니처: 헤더 선언과 `.cpp` 정의를 타입만 비교했다 (파라미터 이름은 무시). 불일치 0. XNU 호출은 `mapDeviceMemoryWithIndex(unsigned int, IOOptionBits = 0)`, `getVirtualAddress(void)`, `getLength(void)`, `getPhysicalAddress(void)` (`IOMemoryDescriptor.h:713`에서 `__LP64__` 가드 밖), `withOptions(IOOptionBits, vm_size_t, vm_offset_t = 1)`, `IODelay(unsigned)`, `PE_parse_boot_argn(const char *, void *, int)` 등과 맞는다.
- 접근성: 호출하는 XNU 멤버 함수 12개 (`mapDeviceMemoryWithIndex`, `registerService`, `probe`, `start`, `stop`, `init`, `free`, `getName`, `getVirtualAddress`, `getLength`, `getPhysicalAddress`, `withOptions`) 전부 `public:` 아래에 있다. 호출 79건 (29+24+26)이 멤버, 정적 헬퍼, XNU 이름 중 하나로 해결된다.
- 매크로 충돌: 0. IO80211/IOAudio 참조: 코드에 0 (주석에만 있다).
- 선례 (SWEET 컴파일 파일 기준): `SweetSurface.cpp`가 `page_size`와 `NULL`을 쓴다. `SweetBattery.cpp`, `SweetCPU.cpp`, `SweetFramebuffer.cpp`가 `uint64_t`/`int64_t`를 쓴다. `SweetCPU.cpp`가 `#if defined(SWEET)` 가드를 쓴다.
- `SWEET` 매크로: `pexpert/pexpert/arm64/SWEET.h:18`에서 `#define SWEET 1`. `board_config.h`가 `ARM64_BOARD_CONFIG_SWEET`일 때 이것을 포함하므로, 가드는 CI의 `MACHINE_CONFIG=SWEET` 빌드에서 참이다.
- `IOKIT_ENABLE_SHARED_PTR`은 `bsd/sweet_hfs/core/hfs_iokit.cpp`에서만 정의된다. 그 TU 안에서만 유효하므로 `withOptions`는 `T*`를 돌려준다.

**한계 (정적 대조가 못 잡는 것):** 실제 플래그로 전처리하지 않았다. 조건부 include는 무시하고 존재 여부로만 판단했다. SDK 플랫폼 헤더 (`sdk-kernel-platform`)는 보지 않았다. 템플릿, 오버로드 해석, 암시적 변환의 세부는 검사하지 않았다. 경고는 `BUILD_WERROR=0`이라 실패가 아니다. **실제 컴파일 검증은 첫 CI run에서만 가능하다.**

## 첫 CI run 후 xnu-cc.py 활성화 절차

`tools/xnu-cc.py`는 수정하지 않았다. 아래는 확인 결과와 **제안**이다.

확인된 사실:
- 환경변수 오버라이드 없음: `CLANG`은 `~/swift/usr/bin/clang`으로 하드코딩 (`tools/xnu-cc.py:25`). `CI_DXB`도 하드코딩 (`:23`). 환경변수는 `XNU_CC_OBJDIR`, `XNU_CC_EXTRA`, `XNU_CC_POST`만 읽는다 (`:94`, `:99`, `:112`).
- `--help` 없음: `main()`이 `sys.argv[2]`를 직접 읽는다 (`:123`). 인자가 부족하면 IndexError.
- 필터 의미: `FILTER`는 전체 CI 경로에 대한 부분 문자열 매칭이다 (`:146`). 새 소스는 같은 CI 로그의 다른 IOKit C++ 명령에서 플래그를 빌려 온다 (`template_for`).
- 포크 이름: `CI_DXB`가 로그 경로와 맞아야 한다. 이름을 바꾸는 것 말고는 로그 쪽을 바꿀 방법이 없다.

**제안 (적용하지 않음, 사용자 승인 필요):**
1. `tools/xnu-cc.py:25`: `CLANG = os.environ.get('XNU_CC_CLANG', os.path.expanduser('~/swift/usr/bin/clang'))`
2. `tools/xnu-cc.py:23`: `CI_DXB = os.environ.get('XNU_CC_CI_DXB', '/Users/runner/work/ios-sweet/ios-sweet/dxb')`
3. `tools/xnu-cc.py:123` 앞: `if len(sys.argv) < 3 or sys.argv[1] in ('-h', '--help'): print(__doc__); sys.exit(0)`

환경변수 방식 (1, 2)이면 도구 수정 없이 재현할 수 있다. 제안 3은 `--help`만 해결한다.

활성화 순서 (첫 CI run 성공 후):
1. 아티팩트를 받는다: `xnu-build-log` (`build.log`)와 `xnu-buildtree` (`buildtree.tgz`).
2. 빌드 트리를 푼다: `mkdir -p $D/bt && tar xzf $D/buildtree.tgz -C $D/bt`.
3. 스위프트 clang이 있는지 확인한다 (`ls ~/swift/usr/bin/clang`). 없으면 4단계 전에 결정한다 (설치, 또는 제안 1 적용).
4. 실행한다:
   `python3 tools/xnu-cc.py $D/build.log $D/bt iokit/Kernel/arm/SweetGPU.cpp iokit/Kernel/arm/SweetWifi.cpp iokit/Kernel/arm/SweetWcd9375Audio.cpp --per-file`
5. 결과를 읽는다. stderr의 `N files, build dirs: [...]`가 나오고, 마지막에 `k of N files failed`가 나온다. `per-file`은 실패 파일과 첫 `error:` 줄 두 개를 보여준다.
6. 실패 메시지별 원인:
   - `no compile commands matched`: 포크 이름 (`CI_DXB`), 필터 경로 (`xnu/` 기준 상대 경로여야 함), 또는 CI 로그에 iokit 명령이 없다.
   - `no build dir for component ...`: 빌드 트리 풀기가 불완전하다 (`build/xnu.obj`의 `meta_features.h` 확인).
   - `error:` 줄: 실제 컴파일 오류다. 0082–0084 오류면 시그니처와 include부터 본다. 이 문서의 정적 대조 결과와 대조한다.
