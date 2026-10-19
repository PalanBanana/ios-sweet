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
