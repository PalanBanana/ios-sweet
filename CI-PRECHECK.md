# CI 사전 점검 (precheck)

`CI-TRIGGER.md` §3의 명령을 실행하기 전에 로컬에서 확인할 여덟 항목이다. 판정은 세 가지다.

- **통과**: 이 머신에서 실제로 확인했다.
- **실패**: 확인했고 맞지 않는다. 옆 칸에 조치를 적었다.
- **미검증**: 확인할 입력이 이 머신에 없거나, 첫 CI run이 있어야 확인된다. 사유를 적었다.

기준 시점: 2026-10-19 (세션 7), 갱신 2026-10-20 (세션 13). 기준 커밋: 세션 13에서 `main`의 HEAD (`a42cd8b`). 로컬 `ci-validate/v1`은 `fd539b9`이며 push 대상이 아니다 (아래 세션 13 절).

## 여덟 항목

| # | 항목 | 판정 | 근거 또는 조치 |
|---|---|---|---|
| 1 | `git apply --check` 84/84 | **통과** | 깨끗한 `xnu-8796.141.3` 워크트리에서 스테이지 스크립트 3개를 먼저 실행한 뒤 패치 84개를 CI 순서로 적용. 스테이지는 SDK 헤더를 placeholder로 받으므로 이 확인은 경로와 문맥만 본다. 0082–0084의 `files.arm64` 앵커는 22/23/24행 (hunk `@@ -22,1`, `@@ -23,1`, `@@ -24,1`, 세션 13 확인). 세션 13 재확인: `a42cd8b`에서 84/84. 조치: 패치를 고쳤다면 같은 절차로 다시 확인 |
| 2 | `tools/test-check-patch-log.sh` 18/18 | **통과** | 합성 로그 18개 케이스 전부 통과 (세션 13 재확인). 실제 CI 로그는 7-1 표의 SUMMARY 줄로 확인했다 |
| 3 | `tools/xnu-cc.py`로 0082–0084 컴파일 | **미검증** | 사유 세 가지. (a) 입력 부재: CI 로그와 `xnu-buildtree`가 없다. 이 트리로는 CI run이 한 번도 없었다. (b) 도구가 `~/swift/usr/bin/clang` (swiftlang 포크)을 하드코딩한다 (`tools/xnu-cc.py:25`). 이 머신에는 없다. (c) 빌드 디렉터리 (`build/xnu.obj`의 Makefile과 `meta_features.h`)는 xnu 빌드가 만든다. 그 빌드의 SDK 해석은 `/usr/bin/xcrun`에 기대며 (`makedefs/MakeInc.cmd:108,124`), 이 머신에는 `/usr/bin/xcrun`이 없다. `--help`는 지원되지 않는다 (`sys.argv[2]`에서 IndexError). 사용법은 `tools/xnu-cc.py` 모듈 설명문에 있다. 조치: 첫 CI run 후 아래 "첫 실행 후 명령"으로 재시도. 1차 입력은 `xnu-build-log`, 2차는 `xnu-buildtree` |
| 4 | `tools/qemu-sweet.py` 스모크 | **미검증** | 사유 세 가지. (a) `qemu-system-aarch64`가 없다 (`qemu-sweet.py:184`가 호출). (b) 커널 산출물이 없다 (`xnu-kernel` 아티팩트는 CI가 만든다). (c) payload는 `mkpayload.py KERNEL ADT`로 만들며 커널이 필요하다. ADT는 `tools/mkadt.py OUT --qemu`로 로컬에서 만들 수 있다 (확인: 4164 바이트, `/product` 노드 없음 경고). 조치: `qemu-system-arm` 설치 (사용자 승인 필요), CI 커널 확보, payload 생성 후 `--kernel`과 `--fail-on-panic`으로 실행 |
| 5 | `origin` push URL `DISABLED` | **통과** | `git remote -v`: fetch는 upstream, push는 `DISABLED`. `git push --dry-run origin main`이 거부됨. 세션 13 재확인: `git remote get-url --push origin` = `DISABLED` |
| 6 | 푸시할 커밋 | **정정 (세션 13)** | 로컬 `ci-validate/v1`은 `fd539b9`다 (세션 7 기록의 `d61ef3c`과도 다르다). `git push fork ci-validate/v1`은 새 커밋을 보내지 않는다. 푸시는 `git push fork HEAD:ci-validate/v1`로 하고, 푸시 전에 `git rev-parse --short HEAD`를 기록한다 |
| 7 | 첫 CI run에서만 확인되는 항목 | **부분 확인 (세션 13)** | 아래 표 7-1. 첫 run의 로그와 아티팩트가 이 머신에 있다 |
| 8 | `CI-TRIGGER.md` §3 명령 블록 | **통과** | `macos_version`, `kernel_config`, `machine_config`, `keep_going` 네 입력이 `xnu.yml`의 `workflow_dispatch` 입력과 일치. `--ref ci-validate/v1` 사용. 명령 목록 (`gh run list/watch/view`) 확인. 세션 13: 자동 실행은 `push: main`뿐이다. `ci-validate/v1` push는 빌드를 시작하지 않으므로 `gh workflow run`이 필요하다 |

### 7-1. 첫 CI run에서 확인할 다섯 항목

| 항목 | 판정 | 근거 | 확인 방법 |
|---|---|---|---|
| `gh run view --log`의 열 구분 (탭 또는 공백) | **확인 (세션 13): 탭** | `tools/xnu-cc.py:36`의 정규식 `^build\s+Build\s+\S+\s+`은 탭과 공백을 모두 허용한다. 그래서 기존 `awk -F'\t'`은 탭이 아니면 틀린다. 플레이북은 기본 FS 방식 (`awk '$1=="build" && $2=="Build"'`)을 쓴다 | `head -n 3 run.txt \| cat -A`. 탭이면 `^I`가 보인다 |
| `if: always()` verify 단계 실행 | **확인 (세션 13, run.log)** | GitHub 문서: `always()`는 앞 단계가 실패해도 실행된다. 이 머신에서 Actions를 실행할 수 없다 | 로그에 `Verify patch application` 단계와 `SWEET_PATCH_SUMMARY` 줄이 있는지 |
| `xnu-build-log` 아티팩트 생성 | **확인 (세션 13, 로컬 파일)** | 워크플로우 `Upload build log` 단계 (`if: always()`) | `gh api repos/<USER>/ios-sweet/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[].name'` |
| 실패 run에 `xnu-kernel` 없음 | **미검증** (규칙상 기대) | `xnu-kernel` 업로드는 `if: success()`. 실패 run에 있으면 워크플로우가 깨진 것 | 위 명령으로 실패 run의 목록 확인. 성공 run에는 `xnu-kernel`이 있어야 한다 |
| SUMMARY 줄 값 | **확인 (세션 13, run.log)** | `SWEET_PATCH_SUMMARY: result=PASS applied=88 skipped=4 baseline_skipped=4 failed=0 ours=84 ours_applied=84 expected_applied=88 stage_scripts=3/3` (줄 1개) | `grep SWEET_PATCH_SUMMARY run.txt` |

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
- `IOKIT_ENABLE_SHARED_PTR`은 TU 단위 `#define`이다 (예: `iokit/Kernel/IOBufferMemoryDescriptor.cpp:28`, `IOCPU.cpp:29`). 전역 정의는 없다 (세션 13 확인). 이 드라이버 TU는 정의하지 않으므로 `withOptions`는 `T*`를 돌려준다. (세션 8의 "hfs TU에서만"은 틀렸다.)

**한계 (정적 대조가 못 잡는 것):** 실제 플래그로 전처리하지 않았다. 조건부 include는 무시하고 존재 여부로만 판단했다. SDK 플랫폼 헤더 (`sdk-kernel-platform`)는 보지 않았다. 템플릿, 오버로드 해석, 암시적 변환의 세부는 검사하지 않았다. 경고는 `BUILD_WERROR=0`이라 실패가 아니다. **실제 컴파일 검증은 첫 CI run에서만 가능하다.**

## 첫 CI run 후 xnu-cc.py 활성화 절차

`tools/xnu-cc.py`는 수정하지 않았다. 아래는 확인 결과와 **제안**이다.

확인된 사실:
- 환경변수 오버라이드 없음: `CLANG`은 `~/swift/usr/bin/clang`으로 하드코딩 (`tools/xnu-cc.py:25`). `CI_DXB`도 하드코딩 (`:23`). 환경변수는 `XNU_CC_OBJDIR`, `XNU_CC_EXTRA`, `XNU_CC_POST`만 읽는다 (`:94`, `:99`, `:112`).
- `--help` 없음: `main()`이 `sys.argv[2]`를 직접 읽는다 (`:123`). 인자가 부족하면 IndexError.
- 필터 의미: `FILTER`는 전체 CI 경로에 대한 부분 문자열 매칭이다 (`:146`). 새 소스는 같은 CI 로그의 다른 IOKit C++ 명령에서 플래그를 빌려 온다 (`template_for`).
- 포크 이름: `CI_DXB`가 로그 경로와 맞아야 한다. 이름을 바꾸는 것 말고는 로그 쪽을 바꿀 방법이 없다.

**제안 (적용하지 않음, 사용자 승인 필요).** 세 제안은 모두 `tools/xnu-cc.py`를 고치므로 적용하면 도구 수정이 한 번 필요하다. 적용하지 않은 이유는 입력 부재다. 첫 CI run의 아티팩트가 없으면 고친 도구를 돌릴 입력이 없다. 최소 diff는 아래와 같다. `ast.parse`로 구문만 확인했고 실행하지는 않았다.

**1. CLANG 경로를 환경변수로 (`tools/xnu-cc.py:25`)**

```diff
-CLANG = os.path.expanduser('~/swift/usr/bin/clang')
+CLANG = os.environ.get('XNU_CC_CLANG', os.path.expanduser('~/swift/usr/bin/clang'))
```

**2. CI_DXB를 환경변수로 (`tools/xnu-cc.py:23`)**

```diff
-CI_DXB = '/Users/runner/work/ios-sweet/ios-sweet/dxb'
+CI_DXB = os.environ.get('XNU_CC_CI_DXB', '/Users/runner/work/ios-sweet/ios-sweet/dxb')
```

**3. `--help` (`tools/xnu-cc.py:123` 앞)**

```diff
 def main():
+    if len(sys.argv) < 3 or sys.argv[1] in ('-h', '--help'):
+        print(__doc__)
+        sys.exit(0)
     log, bt = sys.argv[1], os.path.abspath(sys.argv[2])
```

제안 2는 포크 이름이 `ios-sweet`가 아닐 때 쓴다. CI 로그의 경로는 `/Users/runner/work/<포크 이름>/<포크 이름>/dxb`이고, `CI_DXB`가 그 접두사와 맞아야 한다. 환경변수로 맞추면 상수를 다시 고치지 않아도 된다. 포크 이름을 `ios-sweet`로 두는 것이 가장 단순하다.

**스위프트 clang 설치 결정 체크리스트** (첫 CI run 후, 사용자가 결정):
- [ ] 로그에 iokit C++ 컴파일 줄이 있다: `grep -c "/xnu/iokit/.*\.cpp" build.log`
- [ ] `xnu-buildtree`가 풀리고 `build/xnu.obj`에 `meta_features.h`가 있다
- [ ] swiftlang clang의 출처와 체크섬을 확인했다. 설치 전에 공식 배포처를 확인한다
- [ ] 설치 또는 대체에 사용자가 승인했다
- [ ] 제안 1을 적용할지 결정했다 (적용하면 `CLANG`을 명령 밖에서 지정할 수 있다)
- [ ] 실행 결과 stderr에 `N files, build dirs: [...]`가 나오고, 마지막에 `k of N files failed`가 나온다

**qemu 설치 결정 체크리스트:** 커널 아티팩트 (`xnu-kernel`)가 받아졌다, `tools/mkadt.py --qemu`가 로컬에서 동작한다 (세션 7 확인), `qemu-system-arm` 설치에 승인했다.

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

## 세션 9: 린트와 판정 하네스

- **actionlint v1.7.12** (`~/bin/actionlint`). 릴리스의 `checksums.txt`로 SHA-256을 검증했다 (`8aca8db9…`). 워크플로우 결과: **error 0**, info 1. info는 `Deps` 단계의 `SC2012` (`ls -d /Applications/Xcode*.app`)다. 표시용 명령이라 고치지 않았다.
- **shellcheck v0.11.0** (`~/bin/shellcheck`). 이 릴리스에는 체크섬 자산이 없다. 아카이브 SHA-256 `8c3be12b…`을 기록했고, 내용물이 `shellcheck`, `LICENSE`, `README`뿐임을 확인했다. 정적 링크된 ELF다.
  - 워크플로우의 인라인 `run:` 블록 7개: 오류 0, 경고 0, 노트 1 (`Deps`의 SC2012, actionlint와 같다).
  - `tools/check-patch-log.sh`: 오류 0. 경고 2 (SC2010, `ls | grep`로 패치 이름 필터). 노트 2 (SC2086, 의도된 단어 분리: `printf '%s\n' $LIST`는 따옴표로 묶으면 목록이 한 줄로 합쳐져 `comm` 결과가 틀린다). **CI 판정에 영향이 없어서 고치지 않았다.**
  - `tools/test-check-patch-log.sh`: 경고 2 (SC2010). 고치지 않았다.
  - `tools/post-ci-analyze.sh`: 0건. `tools/test-post-ci-analyze.sh`: SC2028 1건 (`echo`의 백슬래시 이스케이프)을 `printf`로 고쳤다.
- **논리 검토에서 찾은 것:** 읽을 수 없는 로그는 판정은 FAIL로 맞았지만, 우연이었다. 빈 카운터가 `integer expected` 셸 오류를 내고 요약에 `stage_scripts=/3`이 찍혔다. 명시적 `-r` 검사를 추가했고 회귀 케이스를 넣었다 (테스트 18/18).
- **awk 합성 검증** (`tools/test-post-ci-analyze.sh`): 탭 형식과 공백 형식 두 가지 모두에서 Build 단계 97줄을 정확히 뽑는다. 옛 필터 `-F'\t' '$2=="Build"'`는 공백 형식에서 0줄이고, 탭 형식에서도 다른 job의 `Build` 단계 1줄을 더 뽑았다 (98 대 97). job 열을 보지 않았기 때문이다. 실 CI 로그로는 아직 검증하지 않았다.
- **post-ci-analyze.sh**: 합성 fixture 5개 (PASS, FAIL, BUILD_ABORTED_BEFORE_VERIFY, COMPILE_ERROR, UNKNOWN)가 기대 판정과 종료 코드를 낸다. fixture는 실제 체커 출력에서 만들었다.
- **xnu-cc.py 제안 3건**: 구문 검증만 했다 (`ast.parse`, 실행 안 함). 적용하지 않았다.

## 세션 13 (2026-10-20): push 명령 정정, 재확인, sweetgpu 체크리스트 (코드 변경 없음)

**push 명령 (정정).** 로컬 `ci-validate/v1`은 `fd539b9`다. `git push fork ci-validate/v1`은 아무 커밋도 보내지 않는다. 다음을 쓴다.

    git rev-parse --short HEAD        # 기록: 푸시 대상
    git push fork HEAD:ci-validate/v1

fast-forward다 (`fd539b9`의 자손인 `e8e2acb`, `f6bdb2b`, `8272b95`, `a42cd8b`와 세션 13 문서 커밋). 포크의 `ci-validate/v1`이 다른 커밋을 가리키면 git이 거부한다. 거부되면 멈추고 세션 14에 알린다.

**트리거.** `xnu.yml`의 자동 실행은 `push: branches: [main]`뿐이다. `ci-validate/v1`로 push해도 빌드는 시작되지 않는다. 포크에서 Actions가 켜져 있어야 하고, `gh workflow run`으로 수동 실행한다 (CI-TRIGGER.md §3).

**재확인 (이 머신, `a42cd8b`).** 항목 1: 84/84 (깨끗한 worktree, 스테이지 3개 실행). 항목 2: 18/18. 항목 5: `DISABLED`. 항목 8: `workflow_dispatch` 입력 4개 일치.

**첫 run의 근거 (이 머신).**
- `run.log`: SUMMARY 줄 1개 (`result=PASS applied=88 skipped=4 baseline_skipped=4 failed=0 ours=84 ours_applied=84 expected_applied=88 stage_scripts=3/3`). Build 단계 줄 125,761개 (탭 구분). `Verify patch application` 12회.
- 아티팩트: `build-log/build.log` (25 MB), `buildtree-artifact/buildtree.tgz` (23 MB), `kernel-artifact/` (`kernel.development.sweet`, SHA256SUMS 검사 OK).
- 실행 ID `39257384282`는 사용자가 알려준 값이다. 로그와 대조할 수 없다 (`gh run list`로 확인). 빌드 커밋은 로그에 없다. 세션 9 기준 `fd539b9`로 추정한다.

**세션 14 입력 (코드 변경 없음).** NO_UPDATE 불일치 (0082 `0x20C`, Linux `0x0800020C`), TSB/ADDR_MODE 표 (NOTES 세션 13). 다운스트림 zap 조회 방식은 미확정이다.

**sweetgpu=1 하드웨어 테스트 전 체크리스트 (세션 13).** 모두 확인해야 한다. 하나라도 안 되면 실행하지 않는다.
- [ ] personality 없음. 세션 13 확인: `MsmGpuAdreno618`은 0082 패치와 문서에만 있다. `IOKitPersonalities` 항목에 이 클래스가 없고, `allocClassWithName` 호출이 없다.
- [ ] ADT에 GPU 노드 없음. `tools/mkadt.py` 노드 목록: arm-io, asmb, buttons, chosen, cpus, defaults, device-tree, disp0, gic, memory-map, product, sweet-fbcon, sweet-ufs, wdt. GPU 노드가 없다.
- [ ] 이번 부팅에 `sweetgpu=1`을 넣는 것을 사용자가 승인했다. 넣지 않은 부팅 (기본)은 레지스터에 접근하지 않는다.
- [ ] 사용자가 승인했다 (AGENTS.md: 임시 `fastboot boot`, Android와 백업 보존, 파괴적 단계는 사용자 확인).
- [ ] 멈추면 전원 키를 길게 눌러 강제 재시작한다. 재시작 후 `sweetgpu` 없이 부팅해 정상 복귀를 확인한다.

## 세션 14: 실행 명령 (정확한 값)

기준: 세션 14 (2026-10-20). fork `ci-validate/v1`은 이 시점에 `fd539b9`였다 (`git ls-remote fork refs/heads/ci-validate/v1`, 읽기 전용). 실행 전에 같은 값인지 다시 확인한다.

```sh
cd ~/projects/ios-sweet
git status --short                                   # 비어 있어야 한다
git rev-parse --short HEAD                           # 기록 (이번 세션 문서 커밋 포함)
git ls-remote fork refs/heads/ci-validate/v1         # fd539b9여야 한다 (아니면 멈추고 확인)
git push fork HEAD:ci-validate/v1                    # 기대: fd539b9..HEAD, fast-forward, 7커밋
gh workflow run xnu.yml -R PalanBanana/ios-sweet --ref ci-validate/v1 \
  -f macos_version=13.5 -f kernel_config=DEVELOPMENT -f machine_config=SWEET -f keep_going=true
gh run list -R PalanBanana/ios-sweet --workflow xnu.yml --limit 3    # RUN_ID 확인
gh run watch <RUN_ID> -R PalanBanana/ios-sweet
mkdir -p ~/ios-sweet-ci
gh run view <RUN_ID> -R PalanBanana/ios-sweet --log > ~/ios-sweet-ci/run-<RUN_ID>.txt
./tools/post-ci-analyze.sh ~/ios-sweet-ci/run-<RUN_ID>.txt
```

- `git push`에 remote를 생략하면 origin으로 간다. origin은 `DISABLED`다. `fork`를 명시한다.
- 로컬 `ci-validate/v1` (`fd539b9`)은 push 대상이 아니다.
- 판정: `POST_CI_VERDICT: PASS` (exit 0)이면 PASS. 그 외는 `CI-FAILURE-PLAYBOOK.md`를 따른다.

## 세션 15: CI PASS 확정 (run 39350775805)

- 실행 `39350775805`, 빌드 커밋 `ad20b73` (로그의 checkout 줄 `+ad20b73...`). 잡 `build` 7m14s. 아티팩트: `xnu-kernel`, `xnu-buildtree`, `xnu-build-log`.
- 분석: `./tools/post-ci-analyze.sh ~/ios-sweet-ci/run-39350775805.txt` → `POST_CI_VERDICT: PASS (exit 0)`.
- `error:` 11줄은 baseline skip 4개의 `git apply` 메시지다 (컴파일 오류 아님). `SweetGPU.cpp:137` `-Wcast-align` 경고가 하나 있다 (`readFuse`).
- 이 머신 확인 (세션 15): personality 0 (`xnu/` 전체, `.plist` 포함), ADT GPU 0, 체인 84/84, 체크 18/18.
- 다음 코드 변경을 올릴 때는 위 세션 14 절의 명령을 쓴다. push 대상은 새 커밋을 포함한 `HEAD`다.
- `sweetgpu=1` 하드웨어 테스트는 금지 유지다. 컴파일 PASS는 실행 안전성을 뜻하지 않는다 (세션 13 체크리스트 그대로).

## 세션 16: 승인 2+3과 readFuse 정리 (커밋 580e857)

- 승인 1 (펌웨어 조사): 미실행. 폰이 USB에 없다 (`adb devices`에 기기 없음, `lsusb`에 Xiaomi·Qualcomm 장치 없음). 연결과 adb 승인 후 다시 요청한다. 기기 시리얼은 문서에 적지 않는다.
- 코드: `580e857`. TSB 3개 레지스터 (베이스는 lo와 hi), ADDR_MODE 12개 (값 1), `readFuse` 정렬 정리 (warning-only).
- 검증 (이 머신): 체인 84/84, 체크 18/18, 레지스터 검사 (`check_s16.py`) PASS, personality 0, ADT GPU 0, `phone-dump/firmware/sqe_gmu/`는 git이 무시한다 (`.gitignore:13`).
- 푸시 범위: `ad20b73..HEAD` = `3b07636`, `580e857`, 이번 docs 커밋 (3개).

```sh
cd ~/projects/ios-sweet
git ls-remote fork refs/heads/ci-validate/v1          # ad20b73이어야 한다 (아니면 멈추고 확인)
git push fork HEAD:ci-validate/v1                      # fast-forward, 3커밋
gh workflow run xnu.yml -R PalanBanana/ios-sweet --ref ci-validate/v1 \
  -f macos_version=13.5 -f kernel_config=DEVELOPMENT -f machine_config=SWEET -f keep_going=true
gh run list -R PalanBanana/ios-sweet --workflow xnu.yml --limit 3    # RUN_ID 확인
gh run view <RUN_ID> -R PalanBanana/ios-sweet --log > ~/ios-sweet-ci/run-<RUN_ID>.txt
./tools/post-ci-analyze.sh ~/ios-sweet-ci/run-<RUN_ID>.txt
grep -c "SweetGPU.cpp.*warning" ~/ios-sweet-ci/run-<RUN_ID>.txt     # 기대: 0
```

- 기대: `POST_CI_VERDICT: PASS (exit 0)`. `SweetGPU.cpp` 경고 0 (세션 15의 `-Wcast-align`이 사라져야 한다).
- 이 push에는 코드 커밋이 들어 있으므로, CI가 TSB/ADDR_MODE 쓰기 코드를 처음으로 컴파일한다.
- 승인 1 재요청 전: 폰을 USB로 연결하고 adb 승인을 받는다. `adb devices`에 `device` 상태로 보여야 한다.

## 세션 17: GX GDSC 점검과 CP_PROTECT 33 구현 (커밋 `e6bb304`)

- 코드: `e6bb304`. `checkGxPowered()`는 읽기만 한다 (CFG_GDSCR `0x5091010` bit 16을 판정, GDSCR `0x509100c` bit 31을 대조). gpucc 물리 매핑 (`0x5090000`, `0x1014`). CP_PROTECT 33 쓰기 (`0x84F` = `0xB`, `0x850`–`0x86F`). HWCG는 쓰지 않는다 (승인 2 철회).
- 검증 (이 머신): 체인 84/84, `check_s17.py` PASS, `tools/test-check-patch-log.sh` 18/18. 컴파일은 이 머신에서 하지 않았다 (CI 몫). 구현 후 커널 스모크는 CI 아티팩트가 나온 뒤에 한다.
- 기준선 스모크 (구현 전, dec211a 커널, QEMU 60 s): 패닉 없음, `dlil_init`까지 진행. 데이터 어보트 1회는 옛 커널과 같다 (`_skmem_sysctl_init+0x18`). 상세: NOTES 세션 17.
- 푸시 범위: `dec211a..HEAD` = `2a53f73`, `e6bb304`, 이번 문서 커밋 (3개).

```sh
cd ~/projects/ios-sweet
git status --short                                   # 비어 있어야 한다 (kernel-artifact-new/는 .gitignore가 무시한다)
git ls-remote fork refs/heads/ci-validate/v1         # dec211a여야 한다 (아니면 멈추고 확인)
git push fork HEAD:ci-validate/v1                    # 기대: dec211a..HEAD, fast-forward, 3커밋
gh workflow run xnu.yml -R PalanBanana/ios-sweet --ref ci-validate/v1 \
  -f macos_version=13.5 -f kernel_config=DEVELOPMENT -f machine_config=SWEET -f keep_going=true
gh run list -R PalanBanana/ios-sweet --workflow xnu.yml --limit 3    # RUN_ID 확인
gh run watch <RUN_ID> -R PalanBanana/ios-sweet
mkdir -p ~/ios-sweet-ci
gh run view <RUN_ID> -R PalanBanana/ios-sweet --log > ~/ios-sweet-ci/run-<RUN_ID>.txt
./tools/post-ci-analyze.sh ~/ios-sweet-ci/run-<RUN_ID>.txt
grep -c "SweetGPU.cpp.*warning" ~/ios-sweet-ci/run-<RUN_ID>.txt     # 기대: 0
```

- 판정: `POST_CI_VERDICT: PASS (exit 0)`이면 PASS. 그 외는 `CI-FAILURE-PLAYBOOK.md`를 따른다.
- 컴파일 PASS는 실행 안전성을 뜻하지 않는다. `sweetgpu=1` 하드웨어 테스트는 금지 유지다.
- 아티팩트 `xnu-kernel`을 `kernel-artifact-new/`에 받은 뒤 QEMU 스모크를 다시 돌린다 (`mkadt.py OUT.adt --qemu` → `mkpayload.py KERNEL OUT.adt PAYLOAD --cmdline "..."` → `qemu-sweet.py PAYLOAD OUTDIR --secs 60 --fail-on-panic`).

## 세션 19: NO_UPDATE (커밋 a4b0469)

- 코드: `a4b0469`. `CP_RB_CNTL = 0x0800020C` (`kRbCntlDefault | kRbCntlNoUpdate`). 근거: Linux `a6xx_gpu.c:1452-1456`, hw_apriv 0 (`a6xx_catalog.c:762-805`에 HAS_HW_APRIV 없음). `CP_RB_RPTR_ADDR`는 쓰지 않는다 (shadow 없음, `a6xx_gpu.c:1459-1464`).
- 검증 (이 머신): 체인 84/84, `check_s19.py` PASS, `check_s17.py` PASS, `tools/test-check-patch-log.sh` 18/18. 컴파일은 이 머신에서 하지 않았다 (CI 몫).
- 기대 CI 결과: `POST_CI_VERDICT: PASS (exit 0)`, `SweetGPU.cpp` 경고 0.
- 푸시 범위: `dec211a..HEAD` = `2a53f73`, `e6bb304`, `6d3fca4`, `a4b0469`, 이번 문서 커밋 (5개).

```sh
cd ~/projects/ios-sweet
git status --short                                   # 비어 있어야 한다 (kernel-artifact-new/는 .gitignore가 무시한다)
git ls-remote fork refs/heads/ci-validate/v1         # dec211a여야 한다 (아니면 멈추고 확인)
git push fork HEAD:ci-validate/v1                    # 기대: dec211a..HEAD, fast-forward, 5커밋
gh workflow run xnu.yml -R PalanBanana/ios-sweet --ref ci-validate/v1 \
  -f macos_version=13.5 -f kernel_config=DEVELOPMENT -f machine_config=SWEET -f keep_going=true
gh run list -R PalanBanana/ios-sweet --workflow xnu.yml --limit 3    # RUN_ID 확인
gh run view <RUN_ID> -R PalanBanana/ios-sweet --log > ~/ios-sweet-ci/run-<RUN_ID>.txt
./tools/post-ci-analyze.sh ~/ios-sweet-ci/run-<RUN_ID>.txt
grep -c "SweetGPU.cpp.*warning" ~/ios-sweet-ci/run-<RUN_ID>.txt     # 기대: 0
```

- 이 push에서 CI가 GDSC 점검, CP_PROTECT 33, NO_UPDATE를 처음으로 컴파일한다. 컴파일 PASS는 실행 안전성을 뜻하지 않는다. `sweetgpu=1` 하드웨어 테스트는 금지 유지다.

## 세션 20: CI 확인 (run 39397002375 PASS, 빌드 커밋 ebf816e)

- 로그: `~/ios-sweet-ci/run-39397002375.txt`. `SWEET_PATCH_SUMMARY: result=PASS applied=88 skipped=4 baseline_skipped=4 failed=0 ours=84 ours_applied=84 expected_applied=88 stage_scripts=3/3`.
- 빌드 커밋: `ebf816e6450e30cceb31b6b59734abe2ad6eb925` (checkout 로그 줄). `SweetGPU.cpp` 컴파일 줄 있음 (clang++ `-std=gnu++1z`, Xcode 15.0.1). `SweetGPU.cpp` 경고 0. 포함된 XNU 헤더의 공통 경고만 있다.
- 판정: `POST_CI_VERDICT: PASS (exit 0)`.
- 주의: `ls -t ~/ios-sweet-ci/run-*.txt | head -1`은 `.build-tail.txt`를 고른다. 분석은 `run-<RUN_ID>.txt`를 직접 지정한다 (잘못 고르면 "verify step did not run"이 나온다).
- 다음 push 범위: `ebf816e..HEAD` (세션 20 문서 커밋 1개). 먼저 `git ls-remote fork refs/heads/ci-validate/v1`이 `ebf816e`인지 확인한다. 문서만 push하면 CI 재실행은 필요 없다.

## 세션 21: ARC 조회 (`6a5a199`), GMU 창 매핑 (`c656f77`), 문서 (CI 전 점검)

- 로컬 검사 (CI 대체 아님): 체인 84/84 (`run-chain.sh`, 워크트리 `~/refs/xnu-sweet`). 스텁 구문 검사: `bsd/dev/sweet_rpmh.c` 원본과 새 버전 모두 경고 0, 오류 0 (세션 스크래치패드의 `s21-warn-*.txt`). `SweetGPU.cpp` HEAD와 새 버전 모두 경고 0, 오류 0 (`s21c-warn-*.txt`). 스텁은 세션 스크래치패드 (`s21stubs`, `s21gpustubs`)에 있고 저장소 밖이라, 공식 XNU SDK 검사가 아니다.
- CI가 확인할 것:
  1. `bsd/dev/sweet_rpmh.c` (C 파일): 새 `#include <pexpert/pexpert.h>`, `PE_parse_boot_argn("sweetrpmhq", ...)` (int64 버퍼, 최대 8), 정적 함수 `rh_arc_query_one`과 `sweet_rpmh_arc_query` (둘 다 호출되므로 미사용 경고가 없어야 한다), 매크로 `RH_ARC`, `RH_ARC_QUERY_MAX`. 기대: 0062 관련 경고 0.
  2. `SweetGPU.cpp`: 새 `fGmu`, `kGmuPA`/`kGmuBytes` (`static const uint64_t`, `mapPhysical`에서 사용), `static_assert(kGmuPA + kGmuBytes <= 0xB290000, ...)`. 기대: `SweetGPU` 관련 경고 0, 컴파일 줄 존재.
  3. 패치 수는 그대로다 (ours=84). 기대 요약: `applied=88 skipped=4 baseline_skipped=4 ours=84 ours_applied=84 expected_applied=88 stage_scripts=3/3`.
- 로그 분석: `ls -t ~/ios-sweet-ci/run-*.txt | head -1`은 `.build-tail.txt`를 고른다. `run-<RUN_ID>.txt`를 직접 지정한다 (세션 20과 같은 함정).
- push (사용자가 수행, 이 세션은 push하지 않음): 먼저 `git ls-remote fork refs/heads/ci-validate/v1`이 `ebf816e`인지 확인한다. 범위는 `ebf816e..HEAD`다 (세션 20 문서 `44c7503`, 세션 21 커밋 3개). 명령은 `git push fork HEAD:ci-validate/v1` (세션 13 정정).
- 로컬 검사 결과: `check_s17` PASS, `check_s19` PASS, `check_s21_gmu` PASS (스크립트는 세션 스크래치패드, 저장소 밖).
- 기기 쓰기·부팅: 없음.
