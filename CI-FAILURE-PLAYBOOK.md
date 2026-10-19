# CI 실패 플레이북

`CI-TRIGGER.md`로 실행한 `xnu` 워크플로우가 실패했을 때 쓴다. 목표는 실패 원인을 로그 한 번으로 분류하고, 다음 한 수를 정하는 것이다.

## 0. 원칙

- **실패 런의 `xnu-kernel` 아티팩트는 쓰지 않는다.** 이 아티팩트는 모든 앞 단계가 성공했을 때만 업로드된다 (`if: success()`). 실패 런에 있다면 워크플로우 변경이 깨진 것이다. 그 경우 쓰지 말고 보고한다.
- **진단 채널은 세 가지다.** job 로그 (`gh run view --log`), `xnu-build-log` 아티팩트 (14일, 실패해도 항상 업로드), `xnu-buildtree` 아티팩트 (7일, 컴파일 재현용).
- **실패 런에서 받는 순서: `xnu-build-log` → job 로그 → `xnu-buildtree`.** 빌드 출력 전체가 들어 있는 것은 `xnu-build-log`다.
- **push는 `fork` remote에만 한다.** `origin`은 push URL이 `DISABLED`다. 그래도 `origin`을 쓰지 않는다.
- **수정은 `ci-validate/v1` 브랜치에서 커밋한다.** `main`에 커밋한 수정은 push 대상인 브랜치에 들어가지 않는다.
- 로그의 `SWEET_PATCH_SUMMARY` 줄을 **가장 먼저** 본다. 초록불만으로 판정하지 않는다.

## 1. 성공 신호

세 가지가 모두 맞아야 성공이다.

1. `SWEET_PATCH_SUMMARY: result=PASS applied=88 skipped=4 baseline_skipped=4 failed=0 ours=84 ours_applied=84 expected_applied=88 stage_scripts=3/3`
2. `SWEET_PATCH_FAILURE` 줄이 없다.
3. job 결론이 success이고, `xnu-kernel` 아티팩트에 커널과 `SHA256SUMS`가 있다.

## 2. 빠른 분류

먼저 어느 단계에서 깨졌는지 본다.

```sh
gh run view <RUN_ID> -R <USER>/ios-sweet          # 단계별 결론 (success / failure / skipped)
```

| 증상 | 가능한 원인 | 확인 | 다음 행동 |
|---|---|---|---|
| run이 생기지 않거나 즉시 빨간 X, "Invalid workflow file" | 워크플로우 YAML 오류 | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/xnu.yml'))"` | 시나리오 D |
| `SWEET_PATCH_SUMMARY` 줄이 없다 (`Verify patch application` 단계가 skipped 또는 없음) | verify 단계가 실행되지 못함. job이 취소됐거나 앞 단계가 워크플로우 수준에서 실패함 | `gh run view` 단계 목록 | 취소라면 재실행. 아니면 Deps/Fetch 단계 확인 |
| `result=FAIL reason="stage scripts ran X of 3"` | 스테이지 스크립트가 중단됨 (대부분 외부 fetch 실패) | `grep -n "Running script\|error" build.log` | 시나리오 C |
| `result=FAIL reason="no 'Applying patch' lines..."` | 패치 루프 전에 빌드가 중단됨 | build 로그의 첫 `error:` 줄 | Deps/Fetch 또는 build.sh 초반 오류. 로그로 판단 |
| `SWEET_PATCH_FAILURE: skipped <NNNN-이름>` (우리 패치) | 패치가 컨텍스트 불일치로 적용되지 않음 | `grep -n -A4 "Skipping patch.*<이름>" build.log` (git apply 오류 본문) | 시나리오 A |
| `SWEET_PATCH_FAILURE: skipped <blacktop 이름>` | blacktop 쪽 변화 (DXB_SHA 변경, upstream 변경) | 화이트리스트 밖 이름인지 | `tools/check-patch-log.sh`의 `BASELINE_SKIPS` 갱신을 검토 |
| `SWEET_PATCH_FAILURE: not attempted <이름>` | 패치 루프가 중간에 끊김, 또는 로그가 잘림 | 로그 마지막 줄, 파일 크기 | 잘렸으면 재실행. 아니면 시나리오 A |
| `SWEET_PATCH_FAILURE: unexpected applied` / `duplicate applied` | 로그가 두 빌드를 합친 것이거나 `dxb/patches`에 잔여 파일이 있음 | 워크플로우 로그에 빌드가 두 번 있는지 | 재실행. 반복되면 워크플로우 점검 |
| 요약은 PASS인데 `make install` 실패 | 컴파일 오류. 처음 컴파일되는 패치 (0082–0084) 또는 0081 | `grep -n "error:" build.log \| head -50` | 시나리오 B |
| 요약 PASS, make 성공, 그런데 `xnu-kernel`이 없다 | Collect 단계 실패 (fakeroot 경로) 또는 upload 단계 | Collect와 upload 단계 로그 | 시나리오 F |

### 아티팩트 유무의 의미

| 런 결과 | `xnu-kernel` | 의미 |
|---|---|---|
| 실패 | 없음 | 정상. `xnu-kernel`은 검증을 통과한 런에서만 올라온다. 없다는 것만으로 실패의 원인이 되지는 않는다 |
| 실패 | 있음 | 워크플로우 변경이 깨진 것이다. 그 커널은 쓰지 않는다 |
| 성공 | 있음 | 정상. 이 커널만 다음 단계에 쓴다 |
| 성공 | 없음 | Collect 또는 업로드 단계 문제다 (시나리오 F) |

## 3. 로그 회수

```sh
mkdir -p ~/ios-sweet-ci
RUN=<RUN_ID>; R="-R <USER>/ios-sweet"

gh run view $RUN $R --log > ~/ios-sweet-ci/run-$RUN.txt                 # job 로그 전체
gh run view $RUN $R --log-failed > ~/ios-sweet-ci/run-$RUN-failed.txt   # 실패 단계만
gh run download $RUN $R -n xnu-build-log -D ~/ios-sweet-ci/run-$RUN-artifacts   # build.log 원본 (ANSI 포함)
gh run download $RUN $R -n xnu-buildtree -D ~/ios-sweet-ci/run-$RUN-artifacts   # 컴파일 재현용 (7일)
```

요약과 실패 줄은 이렇게 뽑는다.

```sh
F=~/ios-sweet-ci/run-$RUN.txt
grep "SWEET_PATCH_SUMMARY\|SWEET_PATCH_FAILURE" $F
grep -n "error:" $F | head -50
```

Build 단계의 마지막 100줄. `awk`의 기본 필드 분리를 쓴다. 열 구분이 탭이든 공백이든 job 이름(`build`)과 step 이름(`Build`)은 공백이 없으므로 두 형식에서 모두 맞는다.

```sh
awk '$1=="build" && $2=="Build"' $F | tail -n 100
```

**미검증 경고.** 열 구분이 실제로 어떤 형식인지는 아직 확인하지 않았다. `tools/xnu-cc.py:36`의 정규식은 탭과 공백을 모두 허용하도록 쓰였다 (근거 부분 있음). 첫 실행에서 아래로 확인한다.

```sh
head -n 3 $F | cat -A      # 탭이면 ^I가 보인다
```

## 4. 다음 세션에 첨부할 것 (최소)

1. run URL (`gh run view $RUN $R --web`로 열거나 Actions 페이지의 주소)
2. `grep "SWEET_PATCH_SUMMARY\|SWEET_PATCH_FAILURE"` 결과 전체
3. Build 단계의 마지막 100줄
4. `grep -n "error:"` 결과 (최대 50줄)
5. `xnu-build-log` 파일의 경로 (크면 경로만)

## 5. 시나리오별 대응

### A. 패치가 적용되지 않음 (skipped 또는 not attempted, 우리 패치)

1. 워크트리를 초기화하고 같은 순서로 재현한다. 로컬 참조 클론은 저장소 밖에 둔다.

   ```sh
   cd ~/refs/xnu-sweet && git reset -q --hard && git clean -fdq
   # 스테이지 스크립트 3개를 먼저 실행한다 (CI와 같은 순서). 로컬에는 실제 macOS SDK가 없으므로
   # TargetConditionals.h는 placeholder를 쓴다. 이것은 경로 확인만 가능하게 한다.
   for p in $(ls ~/projects/ios-sweet/xnu/patches/*.patch | sort -V); do
     git apply --check "$p" || { echo "FIRST FAIL: $p"; break; }
     git apply "$p"
   done
   ```

2. 첫 실패 패치의 컨텍스트를 실제 파일에 맞춰 고친다.
3. **패치 파일을 직접 편집한다.** 0082–0084는 세션 4 이후 스테이징 디렉터리(scratchpad)에서 만들었다. 그 디렉터리는 세션 사이에 남아 있지 않을 수 있으므로 재생성에 기대지 않는다.
4. 체인을 처음부터 다시 검증한 뒤 커밋하고 push한다.

   ```sh
   # 같은 for 루프가 84개 전부 통과해야 한다
   cd ~/projects/ios-sweet && git switch ci-validate/v1       # 수정은 이 브랜치에서 한다
   git add xnu/patches/NNNN-<이름>.patch                      # 경로로 지정. -a 금지
   git commit -m "xnu NNNN: fix patch context" -m "Co-Authored-By: dipa-studio <183933817+dipa-studio@users.noreply.github.com>"
   git push fork ci-validate/v1                               # fast-forward. force 아님
   gh workflow run xnu.yml -R <USER>/ios-sweet --ref ci-validate/v1 -f keep_going=true
   ```

### B. 컴파일 오류 (`error:`)

1. 로그에서 `file:line`과 오류 본문을 찾는다.
2. `xnu-build-log`를 LOG로, `xnu-buildtree`를 푼 디렉터리를 BUILDTREE로 `tools/xnu-cc.py`를 돌린다. 재현 명령은 다음과 같다 (`CI-PRECHECK.md` 항목 3과 같다).

   ```sh
   D=~/ios-sweet-ci/run-$RUN-artifacts
   mkdir -p $D/bt && tar xzf $D/buildtree.tgz -C $D/bt       # 빌드 트리를 푼다
   python3 tools/xnu-cc.py $D/build.log $D/bt <파일 필터...> --per-file
   ```

   전제 세 가지: (a) `~/swift/usr/bin/clang` (스위프트 포크)이 있어야 한다. 도구가 이 경로를 하드코딩한다 (`tools/xnu-cc.py:25`). (b) 포크 저장소 이름이 `ios-sweet`여야 한다 (`CI_DXB`, `tools/xnu-cc.py:23`). (c) 이 머신에는 XNU 빌드 도구가 없으므로 컴파일은 CI가 만든 빌드 트리에서 한다. 스위프트 clang이 없으면 재현할 수 없다. 설치할지 대체할지는 사용자 결정 사항이다.
3. 소스를 고치고 A의 절차로 체인을 재검증한 뒤 push한다.
4. 0082–0084 드라이버에서 나온 오류라면 `Skipping`이나 `not attempted`가 함께 있는지 본다. 패치 적용 문제와 컴파일 문제가 섞일 수 있다.

### C. 스테이지 스크립트 실패 (`stage scripts ran X of 3`)

1. 로그의 `Running script` 다음 줄에 있는 `error:`를 본다. 대부분 외부 fetch 실패다 (GitHub `libpthread`/`hfs`, `bearssl.org`).
2. 고정 커밋은 불변이다 (`a6c70ca…`, `7bea48e…`, `31d5ec2…`). 커밋이 사라졌다면 외부 문제이므로 기다렸다가 재실행한다.
3. 재실행은 실패한 단계만 다시 돌린다.

   ```sh
   gh run rerun $RUN $R --failed
   ```

### D. 워크플로우 YAML 오류

1. 로컬에서 파싱한다.

   ```sh
   python3 -c "import yaml; yaml.safe_load(open('.github/workflows/xnu.yml')); print('yaml ok')"
   ```

2. 고치고 커밋해서 `fork`에 push한 뒤 다시 dispatch한다. 워크플로우 파일은 dispatch한 ref의 것이 쓰인다.

### E. 러너 환경 (Deps의 brew, KDK 경로, Xcode)

1. `Deps` 단계 로그에서 실패한 명령을 본다.
2. KDK 13.5 경로 (`/Library/Developer/KDKs/KDK_13.5_22G74.kdk`)가 러너에 없으면 빌드가 `KDKROOT not found`로 끝난다. 이 경우는 러너 이미지 문제다. 재실행하거나 사용자와 상의한다.
3. 워크플로우를 바꿔야 하면 사용자 승인을 받는다.

### F. 산출물 문제 (`xnu-kernel` 없음, Collect 실패)

1. `Collect` 단계는 `|| true`라서 실패해도 job은 성공할 수 있다. 그러므로 로그에서 `ls -la out` 출력을 확인한다.
2. 커널 산출물은 **검증이 통과한 런에서만** 쓴다. 통과 런인데도 없다면 `xnu-buildtree`로 빌드 트리의 커널 경로를 확인한다.

## 6. 복구와 force push

- 기본은 **수정 커밋을 쌓아 fast-forward로 push**하는 것이다 (`git push fork ci-validate/v1`).
- 히스토리를 다시 쓰면 (rebase, amend) force push가 필요하다. **이것은 사용자 승인이 있어야 한다.** 승인 후에는 `git push --force-with-lease fork ci-validate/v1`을 쓴다. `--force` 단독은 쓰지 않는다.
- `origin`으로는 어떤 경우에도 push하지 않는다.

## 7. 성공 후 체크리스트

1. 0081 (`sweet_usb.c`)이 컴파일되었는지 로그에서 확인한다 (`sweet_usb` 줄). 이것은 NOTES의 0081 빌드 기록을 채운다.
2. 0082–0084 드라이버 컴파일 오류가 없는지 확인한다. 경고는 무시해도 된다 (`BUILD_WERROR=0`).
3. 통과 시 `NOTES.md`에 CI 실행 ID, 날짜, 결과를 적는다 (AGENTS.md 규칙).
4. 그다음 P1 (SSD 마운트 후 GPU bring-up)을 다음 세션에서 시작한다. QRTR과 SoundWire는 deferred 상태를 유지한다.
