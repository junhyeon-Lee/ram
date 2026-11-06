# 모션 레퍼런스 모음 (기본 동작 퀄리티 올리기)

2026-11-06 수집. 콤보는 나중에 정하고, 먼저 걷기·달리기·박치기·패링·회피의 기본 퀄리티를 올리기 위한 자료다.
저작권: 영상·이미지는 링크만 둔다. 저장소에 받아 두지 않는다(퍼블릭 도메인으로 표시된 Muybridge 도판만 예외로 받아 둘 수 있음).

## 1. 걷기·달리기

| 자료 | 무엇을 얻나 |
|---|---|
| [Bishop et al. 2021, *Science Advances* — 두 발 공룡은 달릴 때 꼬리를 좌우로 흔들었다](https://www.rvc.ac.uk/research/research-centres-and-facilities/structure-and-motion/news/computer-simulations-reveal-dinosaurs-wagged-their-tails-when-running?page=24) ([쉬운 기사](https://www.popsci.com/animals/two-legged-dinosaurs-wagged-tails/), 논문 DOI 10.1126/sciadv.abi7348) | 근육 시뮬레이션 결과 꼬리는 가만히 매달린 균형추가 아니라 **골반·다리 박자에 맞춰 좌우로 크게 흔들리는** 능동적인 부위. 꼬리를 없애면 대신 골반을 흔들어야 했고 근육 부담이 18% 늘었다 |
| [van Bijlert 외 2024 — 에뮤 근육 시뮬레이션: 공룡에게 물려받은 웅크린 자세](https://physics.aps.org/articles/v17/151) | 몸을 낮춘 자세에서는 한 발이 늘 땅에 닿아 있는 **'땅 달리기'**가 가장 효율적. Ram 의 달리기는 높이 뛰기보다 낮고 빠르게 |
| [타조 발가락 관절 연구 (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5237368) | 느리게 걷든 빨리 뛰든 발가락들이 한 덩어리로 움직인다. 발가락은 따로 놀리지 말고 같이 접고 펴기 |
| [Muybridge, *Animal Locomotion* 도판 — 타조 걷기(772)](https://www.nga.gov/collection/art-object-page.167146.html), [염소 걷기(676)](https://www.nga.gov/artworks/220464-plate-number-676-goat-walking), [염소 달리기(679)](https://www.nga.gov/artworks/220466-plate-number-679-goat-galloping) | 실제 동물 연속 사진. 소장 기관이 퍼블릭 도메인으로 표시. 발 닿는 순간·지나가는 순간의 몸 높이를 프레임 단위로 볼 수 있다 |
| [How to Fix Bad Walk Cycles (BlenderNation, 2026)](https://www.blendernation.com/2026/05/28/how-to-fix-bad-walk-cycles/) | 타이밍·무게·골반 회전·겹침(overlap)·발 디딤을 Blender 작업 흐름으로 |
| [Animation Mentor — 자연스러운 걷기](https://workshops.animationmentor.com/courses/animation/how-to-animate-natural-walk-cycles/) | 걷기의 네 자세: **디딤(contact) → 내려앉음(down) → 지나감(passing) → 솟음(up)** |

**Ram 에 적용할 점**
- 지금 걷기·달리기는 디딤·지나감 두 자세뿐이다 → **네 자세(디딤·내려앉음·지나감·솟음)**로 늘린다. 몸이 가장 낮은 때는 디딘 직후(내려앉음), 가장 높은 때는 지나간 직후(솟음).
- **골반 좌우 이동**: 디딘 다리 쪽으로 골반이 실린다. 몸통은 반대로 살짝 기운다.
- **꼬리**: 골반과 엇박으로 좌우 흔들림을 크게(Bishop 2021). 뿌리 → 끝으로 갈수록 늦게 따라오는 겹침.
- **머리**: 몸이 출렁여도 머리는 덜 흔들리게(새처럼 머리를 안정시킴). 돌머리가 화면 중심이라 특히 중요.
- **달리기**: 낮고 웅크린 자세의 땅 달리기. 공중에 뜨는 시간을 짧게.

## 2. 박치기

| 자료 | 무엇을 얻나 |
|---|---|
| [NFB 아카이브 — 큰뿔양 수컷 박치기 슬로모션 44040](https://archives.nfb.ca/stockshot/44040/), [44036](https://archives.nfb.ca/stockshot/44036/), [44038](https://archives.nfb.ca/stockshot/44038/) | **뒷다리로 일어섰다가 떨어지며 들이받는** 동작, 맞는 순간 **몸 전체가 흔들리는** 충격, 옆구리를 들이받는 장면 |
| [Peterson 외 2013 연구 기사 (sci.news)](https://www.sci.news/paleontology/science-head-butting-dome-headed-dinosaurs-01247.html), [Live Science](https://www.livescience.com/24110-dome-headed-dinosaurs.html) | 넓은 돔의 파키케팔로사우루스는 **머리로 밀어붙이기·정면 박치기**, 높은 돔의 작은 종은 **옆구리 들이받기**를 했을 것이라는 해석 (논쟁 중) |
| [Snively & Cox 2008 — 돔 충격 유한요소 해석 (Palaeo-Electronica)](https://palaeo-electronica.org/2008_1/140/index.html) | 돔이 일정 속도의 충격을 견딜 수 있었다. 박치기의 '맞는 순간' 연출 근거 |

**Ram 에 적용할 점 (박치기 변형 3~4개 후보)**
1. **일어섰다 내리찍기**: 큰뿔양처럼 뒷다리로 몸을 세웠다가 떨어지며 박는다 (지금 Attack_Slam 을 크게).
2. **낮은 돌진 박치기**: 몸을 낮추고 달려들어 정면으로 받는다.
3. **옆구리 들이받기**: 몸을 틀어 옆으로 받는다 (지금 Attack_Hook 을 이 방향으로).
4. **밀어붙이기**: 머리를 댄 채 다리로 밀어 상대를 벽으로 민다 (시푸의 벽 활용과 연결).
- 공통: 맞는 순간 Ram 몸에도 **충격 흔들림**(목·꼬리가 한 박자 늦게 출렁).

## 3. 타격감 (모든 공격 공통)

| 자료 | 무엇을 얻나 |
|---|---|
| [Gnomon — Brad Faucheux, 게임·시네마틱 액션 디자인](https://ccs.thegnomonworkshop.com/blog/animating-stylized-attacks-in-maya/) | 실무 애니메이터의 스타일라이즈드 공격 동작 |
| [Slynyrd Pixelblog 9 — 근접 공격](https://slynyrd.com/blog/2018/9/8/pixelblog-9-melee-attacks) | 예비 동작·타격 프레임·회복의 배분 |
| [Wayline — 인디 근접 전투 끌어올리기](https://www.wayline.io/blog/level-up-indie-game-melee-combat) | 히트스톱·화면 흔들림·소리를 한 순간에 맞추기 |

**Ram 에 적용할 점**
- **타격 프레임을 또렷하게**: 맞는 그 한 프레임의 자세가 가장 중요하다. 과장된 자세 + 무거운 공격은 찌그러짐(squash).
- **히트스톱**: 맞는 순간 몇 프레임 멈춘다. 출처마다 숫자가 다르다(가벼운 공격 2~5프레임, 무거운 공격 10프레임 안팎). 시작값으로만 쓰고 직접 만져 보며 맞춘다.
- **예비 동작은 짧게**: 길면 힘 있어 보이지만 입력이 늦게 먹는 느낌이 든다. 회복이 길면 굳은 느낌.
- 멈춤 + 화면 흔들림 + 소리 + 이펙트를 한 순간에 묶는다.

## 4. 패링 (공중제비)

| 자료 | 무엇을 얻나 |
|---|---|
| [캥거루쥐 꼬리 회전 연구 (SICB 초록)](https://sicb.org/abstracts/tail-rotation-facilitates-active-body-reorientation-during-escape-responses-in-kangaroo-rats-d-deserti) | 공중에서 **꼬리를 한 바퀴 휘둘러 몸 방향을 바꾼다**. 꼬리 한 바퀴 0.14~0.2초 동안 몸은 35~55° 돈다 |
| [공중제비 꼬리 타이밍 피드백 (학생 블로그)](https://kharwood.myblog.arts.ac.uk/?p=43) | 꼬리를 정점까지 웅크렸다가 **두어 프레임 만에 휘둘러 내리고**, 착지 뒤 한 번 더 튕긴다 |
| [Polycount — 공중제비 비평](https://polycount.com/discussion/comment/2652358/) | 한 발로만 차고 몸만 웅크리면 가짜 같다. 실제 영상을 보고 몸 각 부분의 순서와 걸리는 시간을 맞출 것 |

**Ram 에 적용할 점**
- 지금의 제자리 수평 회전 → **앞(또는 옆)으로 구르는 공중제비**: 두 다리로 차고 몸을 웅크려 돌머리부터 넘어가고, 꼬리가 크게 원을 그리며 공격을 쳐낸다.
- 꼬리는 정점까지 접어 두었다가 순간적으로 휘두르고, 착지 뒤 한 번 튕긴다.
- 체조 선수 앞구르기 슬로모션 영상으로 몸 순서·시간을 따로 확인한다(아직 수집 안 함).

## 5. 시푸 (전투 레퍼런스)

| 자료 | 무엇을 얻나 |
|---|---|
| [Digital Trends — Sloclap 애니메이션 인터뷰](https://digitaltrends.com/gaming/sloclap-sifu-animation-interview) | 모션 캡처를 그대로 넣지 않는다. 게임플레이 제약에 맞춰 **키프레임으로 다시 다듬는다** |
| [GamesRadar — 시푸 기술 160개](https://www.gamesradar.com/sifu-developers-talk-about-its-160-moves-each-was-designed-for-a-particular-situation) | **기술마다 쓰이는 상황이 정해져 있다** (콤보 설계 때 다시 볼 것) |
| [Unreal Engine — 백미권 고수의 디자인](https://www.unrealengine.com/en-US/developer-interviews/old-boy-john-wick-sifu-the-design-of-a-pak-mei-master) | 실제 쿵후 사범의 동작을 캡처한 뒤 '맞는 순간'을 손으로 더함. 벽에 처박기 같은 **상황별 동작** |
| [GDC Vault — Kung fu and Speed Painting](https://gdcvault.com/play/1028808/Kung-fu-and-Speed-Painting) | 시푸의 시각 정체성 강연 (애니메이션 강연은 찾지 못함) |

## 6. 원리·책

| 자료 | 무엇을 얻나 |
|---|---|
| Jonathan Cooper, [*Game Anim: Video Game Animation Explained*](https://www.routledge.com/Game-Anim-Video-Game-Animation-Explained/Cooper/p/book/9780367707651) (2판 2021), [발췌: 게임 속 12원칙](https://www.gamedeveloper.com/production/the-12-principles-of-animation-in-video-games) | 고전 12원칙을 게임에 맞게 + **게임 애니메이션 5원칙**. 게임 애니메이션 입문서로 가장 직접적 |
| Frank Thomas & Ollie Johnston, *The Illusion of Life* (1981) | 12원칙의 원전 |

## 7. Godot 구현 (발 디딤 IK)

| 자료 | 무엇을 얻나 |
|---|---|
| [Godot 문서 — TwoBoneIK3D](https://docs.godotengine.org/es/4.x/classes/class_twoboneik3d.html) | 4.6 에서 IK 가 돌아왔다. 다리(허벅지·정강이)에 TwoBoneIK3D, 목표점은 발 아래로 쏜 레이가 땅에 닿은 곳 |
| [4.6 IK 소개 글 (tabnews)](https://www.tabnews.com.br/zivaengine/godot-4-6-trouxe-o-ik-de-volta-pra-quem-faz-jogo-3d-isso-importa-mais-que-o-jolt) | 발 디딤 구성 예시 (코드는 미완성이라 참고만) |
| [uhiyama-lab — Godot 3D 스켈레탈 애니메이션](https://uhiyama-lab.com/en/notes/godot/3d-skeletal-animation/) | AnimationTree 블렌딩. 옛 SkeletonIK3D 는 폐기 예정이라 IK 부분은 따라 하지 않는다 |

주의: 위 Godot 문서 링크는 개발 버전 문서다. 실제 구현 전에 4.7 안정판 문서로 다시 확인한다.

## 아직 못 모은 것

- 체조 앞구르기·옆돌기 슬로모션 (패링 공중제비용)
- 캥거루·왈라비 뛰기 영상 (꼬리 균형)
- 스타일라이즈드 공룡이 나오는 게임·애니메이션의 동작 예시
